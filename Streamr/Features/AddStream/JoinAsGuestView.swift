import SwiftUI
import AVFoundation

/// Lets an invited guest join a host's live stream as a second publisher.
///
/// Why this exists at all: the host-side invite produces a *website* URL
/// (`streamr.nyc/livestream?stageArn=…&streamId=…&role=PUBLISH&roomArn=…`), but
/// orca-nebula's `App.tsx` returns `<MobileDesktopOnlyScreen />` for any
/// viewport ≤1023px on every route. So a guest who opens that invite on a phone
/// previously had no route in whatsoever — not a degraded experience, a dead
/// end. This screen accepts the same link inside the app instead.
///
/// Paste-the-link rather than tapping it: opening the app directly from the URL
/// would need a universal link, which requires an
/// `apple-app-site-association` file hosted on streamr.nyc. The App ID already
/// carries the Associated Domains capability, so that's a drop-in upgrade once
/// someone can publish that file — this screen keeps working either way.
struct JoinAsGuestView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = JoinAsGuestViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasJoined {
                    liveContent
                } else {
                    inviteForm
                }
            }
            .streamrBackground()
            .navigationTitle(viewModel.hasJoined ? "You're On Air" : "Join a Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.hasJoined ? "Leave" : "Cancel") {
                        Task {
                            await viewModel.leave()
                            dismiss()
                        }
                    }
                    .foregroundStyle(viewModel.hasJoined ? StreamrColor.liveRed : .white)
                }
            }
        }
    }

    private var inviteForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste the invite link a host sent you, to join their broadcast as a second camera.")
                    .font(StreamrFont.body())
                    .foregroundStyle(.white.opacity(0.75))

                TextEditor(text: $viewModel.inviteText)
                    .frame(height: 100)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await viewModel.join(userId: authManager.currentUser?.id) }
                } label: {
                    ZStack {
                        Text("Join Stream").opacity(viewModel.isJoining ? 0 : 1)
                        if viewModel.isJoining { ProgressView().tint(.black) }
                    }
                    .font(StreamrFont.headline(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(StreamrColor.primary)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.isJoining || viewModel.inviteText.isEmpty)
            }
            .padding(24)
        }
    }

    private var liveContent: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                CameraPreviewView(previewView: viewModel.stageManager.previewView)

                if viewModel.stageManager.connectionState != .connected {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Connecting…")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 24) {
                Button {
                    viewModel.stageManager.toggleMicMuted()
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: viewModel.stageManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        Text(viewModel.stageManager.isMicMuted ? "Unmute" : "Mute")
                            .font(StreamrFont.caption(11))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                if let error = viewModel.stageManager.errorMessage {
                    Text(error)
                        .font(StreamrFont.caption(11))
                        .foregroundStyle(StreamrColor.liveRed)
                        .lineLimit(3)
                }
            }
            .padding(24)
        }
    }
}

@MainActor
final class JoinAsGuestViewModel: ObservableObject {
    @Published var inviteText: String = ""
    @Published private(set) var isJoining = false
    @Published private(set) var hasJoined = false
    @Published private(set) var errorMessage: String?

    /// A publisher-role stage manager, exactly as the host uses — a guest is a
    /// second publisher on the same stage, not a viewer.
    let stageManager = IVSStageManager()

    private var streamId: String?

    /// Pulls the stage/stream ids out of the host's invite link. Accepts a
    /// pasted link with surrounding whitespace or text, since people paste from
    /// chat apps that add both.
    static func parse(_ text: String) -> (streamId: String, stageArn: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "http", options: .caseInsensitive) else { return nil }
        let urlPart = String(trimmed[range.lowerBound...])
            .components(separatedBy: .whitespacesAndNewlines)
            .first ?? ""

        guard let components = URLComponents(string: urlPart) else { return nil }
        let items = components.queryItems ?? []
        guard let streamId = items.first(where: { $0.name == "streamId" })?.value,
              let stageArn = items.first(where: { $0.name == "stageArn" })?.value,
              !streamId.isEmpty, !stageArn.isEmpty else { return nil }
        return (streamId, stageArn)
    }

    func join(userId: String?) async {
        errorMessage = nil

        guard let parsed = Self.parse(inviteText) else {
            errorMessage = "That doesn't look like a Streamr invite link. It should contain streamId and stageArn."
            return
        }
        guard let userId else {
            errorMessage = "Log in before joining as a guest."
            return
        }

        isJoining = true
        defer { isJoining = false }

        // Camera and mic are needed to publish at all, so ask before taking the
        // guest slot — otherwise the slot is consumed by someone who then can't
        // actually go on air, and the host can't invite anyone else.
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard cameraGranted, micGranted else {
            errorMessage = "Camera and microphone access are needed to join as a guest."
            return
        }

        do {
            // Pre-flight against the stream itself. `/stream/guest/user`
            // answers 403 with NO message body, so without this the screen
            // could only show "Request failed with status 403." — reported
            // 2026-10-14 with a screenshot. These are the conditions that
            // actually produce it, named before the request is sent.
            if let detail = try? await APIClient.shared.request(
                API.Streams.viewerDetail(id: parsed.streamId), as: APIResponse<StreamDetail>.self
            ).data {
                if detail.userId?.id == userId {
                    errorMessage = "This is your own stream. Open it from Add Stream instead of joining as a guest — the invite link is for someone else."
                    return
                }
                if detail.isEnded {
                    errorMessage = "This stream has already ended, so there's nothing to join."
                    return
                }
            }

            // Checked next so an already-taken slot reads as a clear message
            // rather than the raw server error the website shows.
            if let check = try? await APIClient.shared.request(
                API.Streams.checkGuest(streamId: parsed.streamId), as: CheckGuestResponse.self
            ), check.guestJoined == true {
                errorMessage = "Someone has already joined this stream as a guest."
                return
            }

            _ = try await APIClient.shared.request(
                API.Streams.guestJoin(streamId: parsed.streamId, userId: userId),
                as: APIResponse<EmptyData>.self
            )

            // Raw response, not envelope-wrapped — same as the host path, see
            // StageTokenResponse's doc comment.
            let tokenInfo = try await APIClient.shared.request(
                API.Streams.getToken(
                    streamId: parsed.streamId, role: .publish,
                    stageArn: parsed.stageArn
                ),
                as: StageTokenResponse.self
            )

            streamId = parsed.streamId
            stageManager.join(token: tokenInfo.token)
            hasJoined = true
        } catch {
            // A bare 403 from the guest endpoints carries no message, so
            // `localizedDescription` is "Request failed with status 403." —
            // true and useless. Say what it means instead.
            if case APIError.server(_, let statusCode) = error, statusCode == 403 {
                errorMessage = "The host's stream isn't accepting a guest right now. That usually means someone else already joined, or the host hasn't enabled guests for this episode. Ask them to send a fresh invite link."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Posts to `/stream/second-publisher-left/{id}`, NOT `/stream/end` — a
    /// guest leaving must not end the host's broadcast.
    func leave() async {
        guard hasJoined, let streamId else { return }
        stageManager.leave()
        _ = try? await APIClient.shared.request(
            API.Streams.guestLeft(streamId: streamId), as: APIResponse<EmptyData>.self
        )
        hasJoined = false
    }
}
