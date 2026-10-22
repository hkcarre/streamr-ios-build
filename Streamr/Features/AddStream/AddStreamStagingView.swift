import AVFoundation
import SwiftUI
import UIKit

/// Real implementation for Stream/Record — camera/mic permission, live
/// preview, Go Live/End Stream. Joins the stage using the token already
/// fetched right after create-stage (see AddStreamCoordinator.beginLiveStage),
/// falling back to fetching its own only if that earlier fetch failed. Also
/// offers Invite Guest here directly — not just via the one-shot toggle on
/// the episode-details screen (AddStreamInviteGuestStepView) — confirmed
/// 2026-09-02 that skipping that toggle left no way to ever invite anyone.
struct AddStreamStagingView: View {
    @ObservedObject var coordinator: AddStreamCoordinator
    @State private var permissionState: PermissionState = .requesting
    @State private var isJoining = false
    @State private var showingInviteShareSheet = false
    /// Snapshot taken at tap time, not read live from `coordinator` inside
    /// the sheet closure — the button is only ever shown/tappable once
    /// `guestInviteURL` is non-nil, but capturing it here means the sheet's
    /// content can't end up blank from a stale/racing @Published read.
    @State private var inviteShareURL: URL?
    @State private var isEnding = false
    /// Seconds published so far this session, driven by `sessionTimer` below.
    @State private var elapsedSeconds = 0
    /// Set when the plan's time ran out, so the host is told why the session
    /// ended rather than just being dropped into "done".
    @State private var hitTimeLimit = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var leftWhilePublishing = false
    @State private var showingInterruptedAlert = false
    @State private var showingEndConfirmation = false
    /// True once an end attempt has been refused by the server — drives the
    /// retry-or-force-stop alert. Without it a failing backend left the host on
    /// air with no working control.
    @State private var endFailed = false
    /// Drives the pulsing dot on the status badge.
    @State private var livePulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PermissionState {
        case requesting, granted, denied
    }

    var body: some View {
        // SCROLLABLE content, with the stop control PINNED below it.
        //
        // This was a plain VStack with no ScrollView. Its children — a 280-320pt
        // camera preview, the status badge, the plan countdown, a multi-line
        // error, and the Go Live / End Stream button — add up past the height of
        // a smaller phone, and with no scroll view SwiftUI compresses and clips
        // instead of scrolling. The button was pushed off the bottom and simply
        // could not be reached, which is why ending a stream was impossible with
        // "no button either" (reported 2026-10-11). The long error shown after a
        // failed end made it worse exactly when the stop control mattered most.
        //
        // A control that takes you off air must never be able to scroll or clip
        // out of reach, so it lives in a `safeAreaInset` that is always on
        // screen regardless of what the content above it does.
        ScrollView {
            VStack(spacing: 20) {
                switch permissionState {
                case .requesting:
                    ProgressView().tint(.white)
                    Text("Requesting camera & microphone access…")
                        .font(StreamrFont.body())
                        .foregroundStyle(.white.opacity(0.75))
                case .denied:
                    deniedContent
                case .granted:
                    grantedContent
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if permissionState == .granted {
                goLiveButton
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            // Clear any stale "Streaming Now" before the screen draws, so it
            // can't open already claiming to be on air.
            coordinator.stageManager.reconcilePublishingState()
            await requestPermissions()
        }
        // Backgrounding mid-broadcast used to be invisible: iOS suspends the
        // app, the camera stops and the IVS connection drops, but `isPublishing`
        // only ever changes from an SDK callback that cannot arrive while
        // suspended — so the host returned to a screen still reading
        // "Streaming Now" while they were off air, and `/stream/end` was never
        // called, leaving the stream Live on the server forever.
        //
        // On return, the stage's real connection state is the source of truth,
        // not the stale flag.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                if coordinator.stageManager.isPublishing { leftWhilePublishing = true }
            case .active:
                if permissionState == .denied {
                    // Coming back from Settings — see deniedContent.
                    Task { await requestPermissions() }
                } else if permissionState == .granted, coordinator.format == .video {
                    // Idempotent, and cheap when the preview survived being
                    // backgrounded — but if iOS tore the camera down there'd
                    // otherwise be nothing to rebuild it.
                    coordinator.stageManager.startPreview()
                }
                let wasInterrupted = leftWhilePublishing
                    && coordinator.stageManager.connectionState != .connected
                leftWhilePublishing = false
                // Clear a stale "Streaming Now" even when we didn't background
                // — the connection can go away without an SDK callback.
                coordinator.stageManager.reconcilePublishingState()
                if wasInterrupted { showingInterruptedAlert = true }
            @unknown default:
                break
            }
        }
        .alert("Couldn't end the stream", isPresented: $endFailed) {
            Button("Try Again") { Task { await endStream() } }
            Button("Stop Broadcasting Anyway", role: .destructive) { forceStop() }
            Button("Keep Broadcasting", role: .cancel) {}
        } message: {
            Text("The server didn't accept the request, so this episode may stay marked as live and might not publish. You can stop broadcasting now either way — tell the team if it keeps happening.")
        }
        .alert("Your broadcast was interrupted", isPresented: $showingInterruptedAlert) {
            Button("End & Save", role: .destructive) { Task { await endStream() } }
            Button("Stay here", role: .cancel) {}
        } message: {
            Text("The connection dropped while Streamr was in the background, so you're no longer on air. End the session to save and publish what you recorded.")
        }
        .confirmationDialog(
            isRecordingSession ? "Stop recording?" : "End this live stream?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(isRecordingSession ? "Stop Recording" : "End Stream", role: .destructive) {
                Task { await endStream() }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(isRecordingSession
                 ? "Your recording will be saved and start processing."
                 : "Viewers will be disconnected and the episode will start processing.")
        }
        .sheet(isPresented: $showingInviteShareSheet) {
            if let inviteShareURL {
                ActivityShareSheet(items: [inviteShareURL])
            }
        }
    }

    /// Permission denial used to be a true dead end, and an expensive one: by
    /// the time this screen appears `beginLiveStage()` has already created a
    /// real stream server-side, so the only escape — Cancel — orphaned that
    /// record. There was no way to Settings and, because permissions were
    /// requested once in `.task`, granting access and coming back left the
    /// screen just as dead.
    ///
    /// Now it offers the jump to Settings, and `scenePhase` re-checks on
    /// return, so granting access continues the flow instead of stranding it.
    /// The copy names only the permissions actually asked for — an audio
    /// episode never requests the camera, but the old message blamed it anyway.
    private var deniedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: coordinator.format == .video ? "video.slash" : "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))

            Text(deniedMessage)
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PrimaryButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

            // A plain button rather than SecondaryButton, which is generic over
            // a required icon ViewBuilder and would need a placeholder here.
            Button("Back to Episode Details") {
                coordinator.step = .episodeDetails
            }
            .font(StreamrFont.body(15))
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var deniedMessage: String {
        coordinator.format == .video
            ? "Streamr needs camera and microphone access to \(isRecordingSession ? "record" : "go live"). Turn them on in Settings, then come back."
            : "Streamr needs microphone access to \(isRecordingSession ? "record" : "go live"). Turn it on in Settings, then come back."
    }

    private var grantedContent: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .top) {
                // A red frame around the picture for as long as the session is
                // running — the convention every camera app uses, and visible
                // from across a room, unlike a small badge.
                if isSessionRunning {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isReconnecting ? StreamrColor.warningGold : StreamrColor.liveRed,
                            lineWidth: 3
                        )
                        .padding(-3)
                        .allowsHitTesting(false)
                        .zIndex(1)
                }

                if coordinator.format == .video {
                    // Portrait-shaped, not a short landscape letterbox.
                    //
                    // The published frame is 9:16 (see
                    // IVSStageManager.makeVideoConfiguration) and the preview
                    // uses `.fit`, so inside the old wide-and-short box the
                    // picture was pillarboxed down to a narrow strip — a
                    // technically correct preview you couldn't actually see
                    // your face in. A 3:4 box leaves the whole frame visible at
                    // a usable size; the screen scrolls and the stop button is
                    // pinned, so taking more height here costs nothing.
                    BroadcastGridView(
                        localPreview: coordinator.stageManager.previewView,
                        guestViews: coordinator.stageManager.guestVideoViews
                    )
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }

                HStack {
                    // IVSStageManager.setMuted already existed but had no UI
                    // control anywhere — confirmed 2026-09-02 as a real gap
                    // found while testing on a real device. A neutral
                    // translucent circle, not brand green: this is a utility
                    // toggle, not a call to action like Invite/Go Live.
                    muteButton

                    if coordinator.format == .video, coordinator.stageManager.canFlipCamera {
                        flipCameraButton
                    }

                    Spacer()
                    // Overlaid directly on the preview (not buried below Go
                    // Live) and filled with the brand green, matching
                    // feedback 2026-09-02 that the outlined/translucent
                    // SecondaryButton version was too easy to miss.
                    if coordinator.guestInviteURL != nil {
                        inviteGuestButton
                    }
                }
                .padding(10)
            }

            statusBadge

            // Says what the preview is, so a host doesn't take the camera
            // coming up as being on air already — the two states look alike,
            // and the badge above is the only other thing distinguishing them.
            if coordinator.format == .video, !isSessionRunning {
                Text("This is your camera preview — nobody else can see it until you \(isRecordingSession ? "start recording" : "go live").")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let remainingLabel {
                Text(remainingLabel)
                    .font(StreamrFont.caption())
                    .foregroundStyle(hitTimeLimit ? StreamrColor.liveRed : .white.opacity(0.7))
            }

            if let errorMessage = coordinator.stageManager.errorMessage ?? coordinator.wizardError {
                Text(errorMessage)
                    .font(StreamrFont.caption())
                    .foregroundStyle(StreamrColor.liveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: coordinator.hasStartedSession) {
            await runSessionTimer()
        }
    }

    /// Counts up while publishing and ends the session when the plan's time is
    /// used up.
    ///
    /// The limit comes from get-token's `allowedStreamInfo.remainingSeconds`
    /// (see AllowedStreamInfo) and is enforced HERE, on the client, because the
    /// backend does not enforce it — verified live 2026-10-11. That makes this
    /// a courtesy stop, not a security control: it keeps an honest host inside
    /// their plan, and it's the same mechanism the website relies on.
    ///
    /// `nil` limit means unlimited and is left alone. Zero means out of time
    /// and stops immediately — the website conflates those two and lets an
    /// exhausted plan stream forever (orca-nebula `livestream.tsx:205-212`).
    private func runSessionTimer() async {
        guard isSessionRunning else {
            elapsedSeconds = 0
            return
        }

        while !Task.isCancelled, isSessionRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            elapsedSeconds += 1

            if let limit = coordinator.streamTimeLimit, elapsedSeconds >= limit, !isEnding {
                hitTimeLimit = true
                await endStream()
                return
            }
        }
    }

    /// Shown only when the plan actually has a limit — an unlimited plan gets
    /// no countdown rather than a misleading one.
    private var remainingLabel: String? {
        guard let limit = coordinator.streamTimeLimit else { return nil }

        if hitTimeLimit {
            return "Your plan's streaming time is used up — ending the session."
        }

        guard isSessionRunning else {
            return "\(formatted(limit)) of streaming time left on your plan."
        }
        return "\(formatted(max(limit - elapsedSeconds, 0))) left in this session."
    }

    private func formatted(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }

    /// Brand-green filled circle + label, not the outlined SecondaryButton
    /// style used elsewhere — this needs to read as its own strong
    /// affordance next to the live preview, not compete quietly with Go
    /// Live. `#9AD0AF` is the confirmed primary brand accent
    /// (StreamrColor.primary); black icon/text on it for contrast, matching
    /// how Go Live already renders on the same color.
    private var inviteGuestButton: some View {
        Button {
            inviteShareURL = coordinator.guestInviteURL
            showingInviteShareSheet = true
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(StreamrColor.primary)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

                Text("Invite")
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            }
        }
    }

    /// Neutral dark-translucent circle, not brand green — a utility toggle,
    /// not a call to action. Works before Go Live too (so you can check the
    /// mic state ahead of time), not just once publishing.
    ///
    /// Calls `setMicMuted`, NOT `setMuted`. `setMuted` mutes every local
    /// stream, the camera included, so the original wiring here took the
    /// broadcaster off air entirely — viewers lost the picture as well as the
    /// sound. State is read back from the stage manager rather than kept in a
    /// local @State, so the icon can't drift out of step with the real device
    /// after a leave/rejoin resets it.
    private var muteButton: some View {
        Button {
            coordinator.stageManager.toggleMicMuted()
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: coordinator.stageManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                Text(coordinator.stageManager.isMicMuted ? "Unmute" : "Mute")
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            }
        }
    }

    /// Front/back switch, in the same neutral style as mute. Shown only when
    /// the device actually has two cameras, and safe to use while publishing —
    /// swapping the camera's input source doesn't interrupt the stream.
    private var flipCameraButton: some View {
        Button {
            coordinator.stageManager.flipCamera()
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                Text("Flip")
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            }
        }
        .accessibilityLabel(coordinator.stageManager.isUsingFrontCamera ? "Switch to back camera" : "Switch to front camera")
    }

    /// Recording and streaming are different acts and now say so. This screen
    /// said "Go Live" / "Streaming Now" for both, so choosing Record and then
    /// being asked to "Go Live" read as though the app was about to broadcast
    /// you publicly — reported 2026-10-11 ("says go live when should say
    /// recording"). A recording isn't published until it's processed, so the
    /// wording shouldn't imply an audience.
    private var isRecordingSession: Bool {
        coordinator.type == .record
    }

    /// Running until the server is told otherwise — see
    /// AddStreamCoordinator.hasStartedSession for why this is not
    /// `isPublishing`.
    private var isSessionRunning: Bool {
        coordinator.hasStartedSession
    }

    /// Session is running but the connection has gone. Worth saying out loud:
    /// silently showing "Recording" while nothing is reaching the server is how
    /// someone records twenty minutes of nothing.
    private var isReconnecting: Bool {
        isSessionRunning && !coordinator.stageManager.isPublishing
    }

    /// Three states, not two. "Ready" before you start, the live state while
    /// connected, and an explicit reconnecting state in between — previously a
    /// dropped connection showed "Ready", which reads as "you never started".
    private var statusBadge: some View {
        let busyLabel = isRecordingSession ? "Recording" : "Streaming Now"
        let label = isReconnecting ? "Reconnecting…" : (isSessionRunning ? busyLabel : "Ready")
        let tint: Color = isReconnecting
            ? StreamrColor.warningGold
            : (isSessionRunning ? StreamrColor.liveRed : Color.white.opacity(0.15))

        return HStack(spacing: 7) {
            if isSessionRunning {
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .opacity(livePulse ? 0.3 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: livePulse
                    )
            }
            Text(label)
                .font(StreamrFont.headline(14))
            if isSessionRunning {
                Text(elapsedLabel)
                    .font(StreamrFont.caption(13))
                    .monospacedDigit()
                    .opacity(0.9)
            }
        }
        .foregroundStyle(isReconnecting ? .black : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint)
        .clipShape(Capsule())
        .onChange(of: isSessionRunning) { _, running in
            livePulse = running
        }
    }

    private var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var goLiveButton: some View {
        let startLabel = isRecordingSession ? "Start Recording" : "Go Live"
        let stopLabel = isRecordingSession ? "Stop Recording" : "End Stream"

        // Keyed on the SESSION, not the connection. A dropped connection used
        // to turn this back into "Start Recording" mid-session, which is both
        // a lie and a trap — the only way out became Cancel.
        return Button {
            if isSessionRunning {
                // Confirmed, not immediate. Deleting one episode already asks
                // (ShowDetailView), and ending a live broadcast is at least as
                // destructive — the same button position flips from start to
                // stop, so a mistap used to take you off air instantly.
                showingEndConfirmation = true
            } else {
                Task { await joinStage() }
            }
        } label: {
            ZStack {
                Text(isSessionRunning ? stopLabel : startLabel)
                    .opacity(isJoining || isEnding ? 0 : 1)
                // Labelled, not a bare spinner: ending deliberately keeps
                // streaming for ~2.5s so the last frames upload, and an
                // unexplained pause there reads as a hang.
                if isJoining || isEnding {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        if isEnding {
                            Text("Finishing up — keep the app open")
                                .font(StreamrFont.caption())
                        }
                    }
                }
            }
            .font(StreamrFont.headline(17))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSessionRunning ? StreamrColor.liveRed : StreamrColor.primary)
            .foregroundStyle(isSessionRunning ? .white : .black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isJoining || isEnding)
    }

    /// Ends the broadcast properly: tell the SERVER first, then tear down the
    /// local stage. Previously this only called `stageManager.leave()`, so the
    /// backend never learned the stream had finished — the episode never
    /// entered Processing and therefore never published to any connected
    /// platform (reported 2026-10-07).
    ///
    /// The brief wait before the backend call mirrors the website, which pauses
    /// ~3s with the stream still flowing so the final frames finish uploading
    /// before `/stream/end` is called. Local publishing continues throughout —
    /// `leave()` only happens after the server has acknowledged.
    ///
    /// If the backend call fails the host stays on this screen with the error,
    /// rather than being dropped into "done" believing the episode was saved.
    private func endStream() async {
        isEnding = true
        defer { isEnding = false }

        // Shared with the Cancel-while-live path — see
        // AddStreamCoordinator.finishLiveSession.
        guard await coordinator.finishLiveSession() else {
            // The server refused. The host stays on air (nothing was torn
            // down), so offer the retry AND a guaranteed way off — otherwise a
            // persistent backend error is a trap with no exit.
            endFailed = true
            return
        }
        coordinator.step = .done
    }

    /// Goes off air immediately without waiting for the server to agree, then
    /// moves on. The deliberate escape from a failing `/stream/end`.
    private func forceStop() {
        coordinator.stopBroadcastingLocally()
        endFailed = false
        coordinator.step = .done
    }

    private func requestPermissions() async {
        let cameraGranted = coordinator.format == .video ? await AVCaptureDevice.requestAccess(for: .video) : true
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        permissionState = (cameraGranted && micGranted) ? .granted : .denied

        // Bring the camera up as soon as permission allows, so there's a live
        // preview to frame against before going live rather than a black box —
        // see IVSStageManager.startPreview.
        if permissionState == .granted, coordinator.format == .video {
            coordinator.stageManager.startPreview()
        }
    }

    private func joinStage() async {
        guard let streamId = coordinator.createdStreamId else { return }
        isJoining = true
        defer { isJoining = false }

        do {
            let token: String
            if let prefetched = coordinator.stageToken {
                token = prefetched
            } else {
                // Raw response, not envelope-wrapped — see StageTokenResponse's
                // doc comment (confirmed live 2026-09-02, same fix as
                // AddStreamCoordinator.fetchStageToken).
                let tokenInfo = try await APIClient.shared.request(
                    API.Streams.getToken(
                        streamId: streamId, role: .publish,
                        stageArn: coordinator.createdStageArn
                    ),
                    as: StageTokenResponse.self
                )
                token = tokenInfo.token
                coordinator.applyAllowedStreamInfo(tokenInfo.allowedStreamInfo)
            }

            coordinator.stageManager.join(token: token)

            // Latched here, before the connection is even up. From this point
            // a session exists server-side, so Stop belongs on screen whatever
            // the connection does next.
            coordinator.sessionDidStart()
            elapsedSeconds = 0

            // You should not have to check your email to find out the thing
            // started (reported 2026-10-14). The badge turns red with a pulsing
            // dot and a running clock, and the phone taps you — the same
            // confirmation a camera app gives.
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Started for BOTH Stream and Record, not just Record.
            //
            // This was gated on `type == .record`, which is why a live stream
            // could be watched fine but produced nothing when you ended it —
            // reported 2026-10-11: "stream live populates and can be watched,
            // but stopping manually does not process publishing". `/stream/end`
            // moves a stream into Processing, and Processing is what publishes
            // to connected platforms, but there has to be a server-side
            // recording in flight for there to be anything to process. Record
            // started one; Stream never did, so ending it had nothing to
            // finish. It matches the symptom exactly: the Record path was
            // reported working ("recorded video auto shared") and only the
            // Stream path failed, and those two differ here and nowhere else.
            //
            // `startRecording` is already idempotent (guarded on `isRecording`)
            // and non-throwing, so it can't tear down a broadcast that's
            // already up — a failure surfaces as a banner instead.
            await coordinator.startRecording()
        } catch {
            coordinator.wizardError = error.localizedDescription
        }
    }
}
