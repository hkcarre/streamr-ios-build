import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    let streamId: String

    @Published private(set) var stream: StreamDetail?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // `isFollowing` and `isLiked` were local, session-scoped flags with no
    // backend behind them — the UI fully committed to the lie (label flipped to
    // "Following", heart filled red) and forgot it on the next visit. Both are
    // gone as of 2026-10-11.
    //
    // Follow is now real, driven by the alert endpoints that genuinely exist
    // (`/user/toggle`, `/user/toggle-alert`) — see PlayerView's FollowButton.
    //
    // Like has no equivalent: there is no like endpoint anywhere in the
    // product, and the website has no such feature either, so the button is
    // removed rather than faked. Restoring it needs a real endpoint first.

    let viewerStageManager = IVSViewerStageManager()
    @Published private(set) var isJoiningLive = false

    let chat = IVSChatManager()
    @Published var chatUnavailableReason: String?

    init(streamId: String) {
        self.streamId = streamId
    }

    /// Only call once `stream` is loaded and confirmed live with a real
    /// stageArn — a "stream"/"record"-type episode gets one from
    /// create-stage, "upload"-type never does (no IVS stage exists for it).
    func joinLiveIfNeeded() async {
        guard let stream, stream.isLive, let stageArn = stream.stageArn,
              viewerStageManager.connectionState == .disconnected else { return }
        isJoiningLive = true
        defer { isJoiningLive = false }

        do {
            let response = try await APIClient.shared.request(
                API.Streams.viewerToken(stageArn: stageArn, streamId: streamId),
                as: ViewerTokenResponse.self
            )
            viewerStageManager.join(token: response.token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaveLive() {
        viewerStageManager.leave()
        chat.disconnect()
    }


    /// Chat needs a roomArn, which the viewer-details payload doesn't carry —
    /// `/stream/chat-room` mints/returns it from the streamId instead. Response
    /// is raw `{message, roomArn}`, not envelope-wrapped.
    ///
    /// Called on demand (when the viewer opens the chat sheet) rather than on
    /// load, so a viewer who never opens chat doesn't pay for a token or hold a
    /// socket open.
    func connectChatIfNeeded(user: User?) async {
        // Retryable: the guard used to be `chat.state == .idle` alone, so once
        // chat had failed, reopening the sheet could never attempt it again —
        // the panel stayed permanently offline for the rest of the stream.
        guard let user, chat.state == .idle || chat.isFailed else { return }
        chatUnavailableReason = nil
        do {
            let room = try await APIClient.shared.request(
                API.Streams.chatRoom(streamId: streamId), as: ChatRoomResponse.self
            )
            guard let roomArn = room.roomArn else {
                chatUnavailableReason = "Chat isn't available for this stream."
                return
            }
            await chat.connect(
                roomArn: roomArn,
                userId: user.id,
                userName: user.fullName,
                userImage: user.profilePic,
                asViewer: true
            )
        } catch {
            chatUnavailableReason = error.localizedDescription
        }
    }

    func load() async {
        guard stream == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.request(
                API.Streams.viewerDetail(id: streamId),
                as: APIResponse<StreamDetail>.self
            )
            stream = response.data
        } catch {
            #if DEBUG
            stream = MockData.streamDetail(id: streamId)
            #else
            errorMessage = error.localizedDescription
            #endif
        }
    }
}
