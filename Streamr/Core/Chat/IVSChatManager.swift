import Foundation
import AmazonIVSChatMessaging

/// Live chat for a stream, wrapping the AWS IVS Chat Messaging SDK.
///
/// Mirrors how the website does it (orca-nebula `ChatArea.tsx`), which is worth
/// stating because the backend has a `/stream/chat-send` endpoint that is a red
/// herring — the website does NOT use it. Messages are sent through the SDK's
/// own socket; the backend's only job is minting a token:
///
///   1. `POST /stream/chat-room {streamId}`      -> roomArn  (already wired)
///   2. `POST /stream/chat-token {roomArn,userId}` -> token   (host/guest)
///      `POST /stream/viewer/chat-token`           -> token   (viewer)
///   3. connect a ChatRoom in region us-east-1 with that token
///   4. send/receive over the socket
///
/// Viewer vs host tokens are different endpoints because a viewer's token
/// carries restricted capabilities — don't substitute one for the other.
///
/// SDK API SURFACE IS UNVERIFIED. This project has no Mac, so the exact Swift
/// signatures below (ChatRoom's initialiser, the delegate method names,
/// SendMessageRequest) are built from AWS's published iOS Chat SDK
/// documentation and the JS SDK's shape. Same treatment as
/// IVSStageManager/IVSViewerStageManager when those were first written: if
/// anything has drifted, the compiler error from CI is the correction. Keep
/// that in mind before assuming a build failure here is a logic bug.
@MainActor
final class IVSChatManager: NSObject, ObservableObject {
    struct Message: Identifiable, Equatable {
        let id: String
        let content: String
        /// The sender's Streamr user id, when it is known.
        ///
        /// Optional because the website doesn't send one: it puts only
        /// `userName`/`userImage` into the IVS message attributes, and this
        /// client matched those keys so messages look identical whichever app
        /// sent them. iOS now also sends `userId`, so a message from this app
        /// can be blocked exactly; one from the website falls back to the
        /// display name. See ModerationStore for why that distinction matters.
        let userId: String?
        let userName: String
        let userImage: String?
        let sentAt: Date

        /// True for messages this device sent, so the UI can align them right.
        var isMine: Bool = false
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var canSend = false

    private var room: ChatRoom?
    private var myUserId: String = ""
    private var myUserName: String = ""
    private var myUserImage: String?

    /// `asViewer` picks which token endpoint to use. Pass the stream's roomArn
    /// (from `/stream/chat-room`) and the signed-in user's id.
    func connect(roomArn: String, userId: String, userName: String, userImage: String?, asViewer: Bool) async {
        guard state == .idle || isFailed else { return }
        guard !roomArn.isEmpty, roomArn != "undefined" else {
            // The website guards on the literal string "undefined" too — the
            // backend has been seen returning it rather than omitting the field.
            state = .failed("This stream doesn't have a chat room.")
            return
        }

        myUserId = userId
        myUserName = userName
        myUserImage = userImage
        state = .connecting

        do {
            let endpoint = asViewer
                ? API.Streams.viewerChatToken(roomArn: roomArn, userId: userId)
                : API.Streams.chatToken(roomArn: roomArn, userId: userId)

            // WRAPPED envelope whose `data` is a bare token string — see the
            // endpoint's doc comment.
            let response = try await APIClient.shared.request(endpoint, as: APIResponse<String>.self)
            guard let token = response.data, !token.isEmpty else {
                state = .failed(response.message ?? "Couldn't get a chat token.")
                return
            }

            // `asyncTokenProvider:`, NOT `tokenProvider:` — the latter takes a
            // `ChatTokenProvider` object, while this overload takes
            // `ChatToken.AsyncProvider` (`() async throws -> ChatToken`), which
            // is what a closure satisfies.
            let room = ChatRoom(
                awsRegion: "us-east-1",
                asyncTokenProvider: { ChatToken(token: token) }
            )
            room.delegate = self
            self.room = room
            try await room.connect()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Not async: the SDK's `sendMessage(with:onSuccess:onFailure:)` is
    /// completion-based, not `async throws`. Failures arrive on `onFailure`
    /// rather than as a thrown error.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let room else { return }

        // `attributes` carries display identity, matching the web app's keys
        // exactly so messages from either client render the same.
        room.sendMessage(
            with: SendMessageRequest(
                content: trimmed,
                attributes: [
                    "userName": myUserName,
                    "userImage": myUserImage ?? "",
                    // Additive: the web client ignores attribute keys it
                    // doesn't know, so sending this can't change how a message
                    // renders there. It exists so a viewer can block a
                    // specific account rather than a display name anyone can
                    // copy.
                    "userId": myUserId
                ]
            ),
            onFailure: { [weak self] error in
                Task { @MainActor in self?.state = .failed(error.localizedDescription) }
            }
        )
    }

    func disconnect() {
        room?.disconnect()
        room = nil
        state = .idle
        canSend = false
        messages = []
    }

    /// Internal, not private: PlayerViewModel needs it to allow a retry after a
    /// failed connect (its guard was `.idle` only, which made failure permanent
    /// for the rest of the stream).
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func append(_ message: ChatMessage) {
        // `Chat.Attributes` is [String: String], and `attributes` is optional.
        let attrs: [String: String] = message.attributes ?? [:]
        let name = attrs["userName"] ?? "Viewer"
        let senderId = attrs["userId"].flatMap { $0.isEmpty ? nil : $0 }
        messages.append(
            Message(
                id: message.id,
                content: message.content,
                userId: senderId,
                userName: name,
                userImage: attrs["userImage"].flatMap { $0.isEmpty ? nil : $0 },
                sentAt: message.sendTime,
                // Prefer the id: two viewers can pick the same display name,
                // and a name comparison then renders a stranger's message as
                // though this device had sent it.
                isMine: senderId.map { $0 == myUserId } ?? (name == myUserName)
            )
        )
        // Keep memory bounded on a long stream — the UI only ever scrolls back
        // so far, and an unbounded array on a multi-hour broadcast is a leak.
        if messages.count > 300 {
            messages.removeFirst(messages.count - 300)
        }
    }
}

/// `ChatRoomDelegate` is an @objc protocol, so these are nonisolated and hop to
/// the main actor themselves. Only `room(_:didReceive:)` is required; the
/// connection-state callbacks are optional.
///
/// There is deliberately no error callback here — the SDK has none. Connection
/// failures surface from `connect()`'s own `async throws`, and send failures
/// through `sendMessage`'s `onFailure`.
extension IVSChatManager: ChatRoomDelegate {
    nonisolated func room(_ room: ChatRoom, didReceive message: ChatMessage) {
        Task { @MainActor in append(message) }
    }

    nonisolated func roomDidConnect(_ room: ChatRoom) {
        Task { @MainActor in
            state = .connected
            canSend = true
        }
    }

    nonisolated func roomIsConnecting(_ room: ChatRoom) {
        Task { @MainActor in state = .connecting }
    }

    nonisolated func roomDidDisconnect(_ room: ChatRoom) {
        Task { @MainActor in
            if state == .connected { state = .idle }
            canSend = false
        }
    }
}
