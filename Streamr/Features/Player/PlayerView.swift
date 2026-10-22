import AVKit
import Combine
import SwiftUI

/// The wireframe's "Player — Video/Audio" screen — the single biggest gap
/// flagged in the 2026-08-08 wireframe review (no AVPlayer/player screen
/// existed anywhere in the app before this, so cards in Discover were dead
/// ends). Real VOD/replay playback (AVPlayer, once a real videoURL exists)
/// plus the surrounding chrome — status badge, title, description, tags,
/// and a working Share button (the native OS share sheet, reusing
/// `ActivityShareSheet` already proven out for guest invites).
///
/// Live in-progress viewing — built 2026-10-04, the other biggest gap found
/// comparing this app against the live website rather than just the
/// wireframe (the website has a dedicated SingleLive page distinct from
/// SingleStream/VOD; this app only ever had the VOD half). Joins the same
/// AWS IVS stage the host is broadcasting to, SUBSCRIBE-only, via
/// IVSViewerStageManager — mirrors orca-nebula's SingleLive.tsx/
/// joinStageCommon exactly. No chat, no mute toggle, no multi-guest grid
/// layout in this pass — scoped to "can a viewer actually watch", the part
/// that didn't exist at all before.
struct PlayerView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var moderation: ModerationStore
    @StateObject private var viewModel: PlayerViewModel
    @State private var player: AVPlayer?
    @State private var showingShareSheet = false
    @State private var showingChat = false
    /// Non-nil while the report sheet is up. See ReportSubject.
    @State private var reporting: ReportSubject?
    @State private var isLiveFullScreen = false
    /// False until AVPlayer reports the item playable — drives the loading
    /// cover over the video surface.
    @State private var isVideoReady = false
    /// Held alongside `player` purely so its `status` can be observed.
    @State private var playerItem: AVPlayerItem?
    /// Only built once a signed-in user, the host's id and the show's id are
    /// all known — the alert endpoints need all three, and none is guaranteed
    /// at init time.
    @State private var followViewModel: AlertMeViewModel?
    /// Set by the show page's "Video On / Audio Only" switch. When off, the
    /// AVPlayer still plays (audio continues) but the video surface is replaced
    /// by the cover art — the point is listening, not stopping playback.
    @AppStorage(PlaybackPreference.prefersVideoKey) private var prefersVideo = true

    init(streamId: String) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(streamId: streamId))
    }

    var body: some View {
        ScrollView {
            if let stream = viewModel.stream {
                content(for: stream)
            } else if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 100)
            } else if let errorMessage = viewModel.errorMessage {
                // `load()` is guarded on `stream == nil` and only fired from
                // `.task`, so without an explicit retry this screen could never
                // recover — the only way back was to pop and re-tap the
                // episode, which is not obvious from a wall of error text.
                VStack(spacing: 16) {
                    Text(errorMessage)
                        .font(StreamrFont.body())
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    PrimaryButton(title: "Try Again") {
                        Task {
                            await viewModel.load()
                            await viewModel.joinLiveIfNeeded()
                        }
                    }
                }
                .padding(.top, 100)
                .padding(.horizontal, 32)
            }
        }
        .streamrBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.stream?.showId?.name ?? "")
                    .font(StreamrFont.headline(16))
                    .foregroundStyle(.white)
            }
            // Report / block. Required by App Store Review Guideline 1.2 for
            // any app showing user-generated content, and this screen is where
            // someone actually encounters something objectionable. Offered
            // whether or not they are signed in: a viewer who cannot sign in
            // still needs a way to report what they are being shown.
            ToolbarItem(placement: .topBarTrailing) {
                moderationMenu
            }
        }
        .task {
            await viewModel.load()
            await viewModel.joinLiveIfNeeded()
            await prepareFollowIfPossible()
        }
        .onDisappear {
            savePlaybackPosition()
            viewModel.leaveLive()
        }
        // Chat is only meaningful on a live stream, and only for a signed-in
        // user — the token endpoints take a userId.
        .overlay(alignment: .bottomTrailing) {
            if isLiveViewable, authManager.isAuthenticated {
                Button {
                    showingChat = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(StreamrColor.gradientStart.opacity(0.92)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .padding(20)
                .accessibilityLabel("Open live chat")
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatPanelView(
                chat: viewModel.chat,
                unavailableReason: viewModel.chatUnavailableReason,
                onRetry: {
                    Task { await viewModel.connectChatIfNeeded(user: authManager.currentUser) }
                }
            )
            .presentationDetents([.medium, .large])
            .task { await viewModel.connectChatIfNeeded(user: authManager.currentUser) }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = viewModel.stream?.shareURL {
                ActivityShareSheet(items: [url])
            }
        }
        .sheet(item: $reporting) { subject in
            ReportSheet(subject: subject)
        }
        // A cover rather than a rotation or a resized inline frame: it takes
        // the whole screen including under the status bar, and it leaves the
        // SAME stage manager rendering, so going full screen never interrupts
        // playback or re-subscribes.
        .fullScreenCover(isPresented: $isLiveFullScreen) {
            LiveFullScreenView(
                stageManager: viewModel.viewerStageManager,
                isJoining: viewModel.isJoiningLive,
                onClose: { isLiveFullScreen = false }
            )
        }
    }

    @ViewBuilder
    private func content(for stream: StreamDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            mediaArea(for: stream)

            statusBadge(for: stream)

            Text(stream.title ?? "Untitled Episode")
                .font(StreamrFont.title(22))
                .foregroundStyle(.white)

            if let hostName = stream.userId?.displayName, !hostName.isEmpty {
                Text(hostName)
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.65))
            }

            actionRow

            if let description = stream.description, !description.isEmpty {
                Text(description)
                    .font(StreamrFont.body(15))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let tags = stream.tags, !tags.isEmpty {
                tagRow(tags)
            }
        }
        .padding(20)
    }

    private var isLiveViewable: Bool {
        guard let stream = viewModel.stream else { return false }
        return stream.isLive && stream.stageArn != nil
    }


    /// Audio-only playback is a real mode with its own controls, not video
    /// playback with the picture hidden — see AudioTransportView for what was
    /// broken before.
    ///
    /// True either because the viewer turned "Video On" off, or because the
    /// episode is an audio episode and never had a picture to show.
    /// Guests simply don't get the button, rather than being shown one that
    /// prompts for login — matching how the show page handles the same control.
    private func prepareFollowIfPossible() async {
        guard followViewModel == nil,
              let userId = authManager.currentUser?.id,
              let creatorId = viewModel.stream?.userId?.id,
              let showId = viewModel.stream?.showId?.id else { return }

        let model = AlertMeViewModel(userId: userId, creatorId: creatorId, showId: showId)
        followViewModel = model
        await model.load()
    }

    private func audioOnlyMode(for stream: StreamDetail) -> Bool {
        !prefersVideo || stream.format == .audio
    }

    @ViewBuilder
    private func mediaArea(for stream: StreamDetail) -> some View {
        let isAudioOnly = audioOnlyMode(for: stream)

        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(StreamrColor.surfaceDark)

                if isLiveViewable {
                    LiveViewerContent(stageManager: viewModel.viewerStageManager, isJoining: viewModel.isJoiningLive)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // Live playback is a hand-built IVS renderer, not
                        // AVPlayerViewController, so it gets none of AVKit's
                        // controls for free — it had no expand and no volume at
                        // all. Recorded episodes already have both from AVKit;
                        // this gives the live path the same two.
                        .overlay(alignment: .bottomTrailing) {
                            LivePlaybackControls(
                                stageManager: viewModel.viewerStageManager,
                                isFullScreen: false,
                                onToggleFullScreen: { isLiveFullScreen = true }
                            )
                        }
                } else if let player, !isAudioOnly {
                    // AVPlayerViewController, not SwiftUI's VideoPlayer — the
                    // latter can't be asked for full screen or PIP at all.
                    VideoPlayerContainer(player: player, entersFullScreenOnPlay: true)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // Episodes are progressive MP4 served straight from S3,
                        // so a long one can sit for a while before AVPlayer
                        // reports readyToPlay and AVKit draws its controls. That
                        // wait used to be an unexplained black rectangle
                        // ("latency until the play button shows up",
                        // 2026-10-11). Showing the episode's own artwork and a
                        // spinner doesn't make the file arrive sooner, but it
                        // replaces a dead screen with something that reads as
                        // loading.
                        .overlay {
                            if !isVideoReady {
                                videoLoadingCover(for: stream)
                            }
                        }
                        .onReceive(itemStatusPublisher) { status in
                            isVideoReady = status == .readyToPlay
                        }
                } else if let coverPicURLString = stream.coverPicURLString, let url = URL(string: coverPicURLString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: stream.format == .audio ? "waveform" : "video.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if !isLiveViewable, player == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "play.slash")
                            .font(.system(size: 22))
                        Text(unavailableMessage(for: stream))
                            .font(StreamrFont.caption())
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 24)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            // The only transport controls in audio-only mode. Keyed on the
            // player's identity so switching episodes rebuilds the observer
            // against the new one.
            if let player, !isLiveViewable, isAudioOnly {
                AudioTransportView(player: player)
                    .id(ObjectIdentifier(player))
            }
        }
        .onAppear { setUpPlayerIfNeeded(for: stream) }
    }

    /// Observes the ITEM's own `status`, not `\.currentItem?.status` on the
    /// player: an optional-chained key path has to survive the round trip
    /// through an Objective-C KVO key string, and `\AVPlayerItem.status` is a
    /// plain KVO-compliant property with no such question over it. Empty until
    /// there's an item, so the view builds the same either way.
    private var itemStatusPublisher: AnyPublisher<AVPlayerItem.Status, Never> {
        guard let playerItem else {
            return Empty<AVPlayerItem.Status, Never>().eraseToAnyPublisher()
        }
        return playerItem.publisher(for: \.status).eraseToAnyPublisher()
    }

    /// Artwork plus a spinner over the video surface while the file loads.
    /// Non-interactive, so it can't swallow a tap meant for AVKit's controls
    /// in the moment it's being torn down.
    @ViewBuilder
    private func videoLoadingCover(for stream: StreamDetail) -> some View {
        ZStack {
            if let coverPicURLString = stream.coverPicURLString, let url = URL(string: coverPicURLString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .overlay(Color.black.opacity(0.45))
            } else {
                StreamrColor.surfaceDark
            }

            ProgressView().tint(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }

    private func setUpPlayerIfNeeded(for stream: StreamDetail) {
        // `playbackURL`, not `videoURL` — the raw field can be cleartext http,
        // which iOS refuses outright. See StreamDetail.playbackURL.
        guard !isLiveViewable, player == nil, let url = stream.playbackURL else { return }
        AVAudioSession.configureForPlayback()

        // `preferPreciseDurationAndTiming: false` keeps AVFoundation from
        // building a precise timing index up front. On a progressive MP4 that
        // can mean reading far more of the file than playback needs, and this
        // screen only ever needs approximate duration for the scrubber and the
        // resume position.
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)

        // Start on enough data to begin rather than on AVPlayer's estimate that
        // it can finish without stalling. On a large single-bitrate file from
        // S3 that estimate is what keeps the controls hidden longest. The cost
        // is a possible stall on a bad connection, which is the better trade
        // for a replay you can scrub — and it changes nothing once buffered.
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        // Pick up where this viewer left off — see PlaybackProgressStore.
        // Seeking before the asset has loaded is fine: AVPlayer queues it and
        // applies it once the item is ready.
        if let resumeAt = PlaybackProgressStore.position(for: viewModel.streamId) {
            newPlayer.seek(
                to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        playerItem = item
        player = newPlayer
    }

    /// Records the position on the way out, for both the video and audio-only
    /// paths — `AVPlayerViewController` and `AudioTransportView` drive the same
    /// `AVPlayer`, so one save covers both.
    private func savePlaybackPosition() {
        guard let player, !isLiveViewable else { return }
        let seconds = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        PlaybackProgressStore.save(
            seconds,
            duration: duration.isFinite ? duration : 0,
            for: viewModel.streamId
        )
    }

    /// Report / block menu for the episode on screen.
    ///
    /// Both actions need an author to act on, so the menu degrades to a single
    /// disabled-looking entry when the detail payload hasn't arrived yet rather
    /// than offering a block that would key on an empty string. A blocked
    /// creator's episodes disappear from the discover lists (see
    /// DiscoverViewModel), but not from this screen — someone who arrived by
    /// direct link should still be told what happened instead of staring at a
    /// player that silently refuses to work.
    @ViewBuilder
    private var moderationMenu: some View {
        Menu {
            if let subject = reportSubject {
                Button {
                    reporting = subject
                } label: {
                    Label("Report this episode", systemImage: "flag")
                }
                Button(role: .destructive) {
                    moderation.block(subject.blockKey, displayName: subject.authorName)
                } label: {
                    Label("Block \(subject.authorName)", systemImage: "person.slash")
                }
            } else {
                Text("Still loading this episode")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Report or block")
    }

    /// Nil until the detail call returns, because every field below comes from
    /// it. `userId` is the host, which is who a report is about.
    private var reportSubject: ReportSubject? {
        guard let stream = viewModel.stream else { return nil }
        let host = stream.userId
        let name = host?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return ReportSubject(
            kind: .episode,
            contentId: stream.id,
            contentDescription: stream.title ?? "",
            authorId: host?.id,
            authorName: name.isEmpty ? "this creator" : name
        )
    }

    private func unavailableMessage(for stream: StreamDetail) -> String {
        if stream.isScheduled { return "This episode hasn't started yet." }
        // The lobby before a broadcast begins — the host is set up but hasn't
        // pressed Start. Worth naming, because it is the one state where
        // waiting is the right thing to do.
        if stream.isStaging { return "The host is about to go live. Check back in a moment." }
        if stream.isProcessing { return "This episode has finished and is still processing. The replay will appear shortly." }
        if stream.isEnded { return "Replay isn't available yet." }
        return "Live playback isn't available for this stream."
    }

    private func statusBadge(for stream: StreamDetail) -> some View {
        Text(stream.statusLabel)
            .font(StreamrFont.caption(11))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(stream.isLive ? StreamrColor.liveRed : StreamrColor.surfaceDark)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    /// Matches the wireframe's Follow+/Like/Share row. Follow/Like are
    /// local-only — see PlayerViewModel's doc comment for why there's no
    /// backend call behind them yet. Share is real: native share sheet with
    /// a best-effort public link (see StreamDetail.shareURL).
    /// Follow is now REAL. It was a local `@Published` flag that flipped the
    /// label to "Following", filled the icon, and forgot everything the moment
    /// you navigated away — an optimistic update with nothing behind it.
    ///
    /// Rather than invent a parallel endpoint, it drives the alert toggle that
    /// already exists and is confirmed live (`/user/toggle`,
    /// `/user/toggle-alert`): following a show means being told when it goes
    /// live, which is what that endpoint does. The show page's "Alert me"
    /// control is the same state, so the two now agree.
    ///
    /// Like has been REMOVED rather than left lying. There is no like endpoint
    /// anywhere in the product — the website has no such feature either — so a
    /// heart that filled in and emptied again on the next visit was worse than
    /// no heart. Share stays; it is genuinely real.
    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 28) {
            if let followViewModel {
                FollowButton(viewModel: followViewModel)
            }

            actionButton(systemImage: "square.and.arrow.up", label: "Share", tint: .white) {
                showingShareSheet = true
            }

            Spacer()
        }
    }

    private func actionButton(systemImage: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(StreamrFont.caption(11))
            }
            .foregroundStyle(tint)
            // These stacks were roughly 30-40pt and below the 44pt minimum.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func tagRow(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(StreamrFont.caption(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(StreamrColor.surfaceDark)
                        .foregroundStyle(.white.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

/// Follow, backed by the real alert toggle. An @ObservedObject subview for the
/// same reason as ShowDetailView's AlertMeButton: PlayerView holds the model as
/// plain @State (its identity, not its @Published internals), so inline content
/// wouldn't re-render when the toggle lands.
///
/// Toggles the CREATOR alert specifically — "follow this show's host" is the
/// closest match to what a Follow button means, and `/user/toggle-alert`
/// treats show and creator as mutually exclusive anyway.
private struct FollowButton: View {
    @ObservedObject var viewModel: AlertMeViewModel

    var body: some View {
        Button {
            Task { await viewModel.toggle(.creator) }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Image(systemName: viewModel.isActive ? "checkmark" : "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .opacity(viewModel.isLoading ? 0 : 1)
                    if viewModel.isLoading {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    }
                }
                Text(viewModel.isActive ? "Following" : "Follow")
                    .font(StreamrFont.caption(11))
            }
            .foregroundStyle(viewModel.isActive ? StreamrColor.primary : .white)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel(viewModel.isActive ? "Following. Tap to unfollow." : "Follow")
    }
}

/// A dedicated @ObservedObject-backed subview, not a computed property on
/// PlayerView — same reasoning as ShowDetailView's AlertMeButton.
/// PlayerView only holds `viewModel.viewerStageManager` by reference
/// through its own @StateObject `viewModel`; SwiftUI's dependency tracking
/// only follows the object actually marked @ObservedObject/@StateObject in
/// a given view, so a computed property reading `viewerStageManager`'s
/// @Published properties wouldn't re-render when remote video actually
/// arrives — this subview observing it directly is what makes that happen.
///
/// Lays every subscribed participant out in a grid. Audio from all of them
/// Mute and full-screen for live playback, in the bottom-right corner the way
/// every video player puts them.
///
/// Its own @ObservedObject subview, not inline content on PlayerView: the mute
/// icon reflects `stageManager.isMuted`, and PlayerView doesn't observe the
/// stage manager — only `LiveViewerContent` does. Inline content would show a
/// speaker icon that never changed when tapped.
private struct LivePlaybackControls: View {
    @ObservedObject var stageManager: IVSViewerStageManager
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            button(
                icon: stageManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: stageManager.isMuted ? "Unmute" : "Mute"
            ) {
                stageManager.toggleMuted()
            }

            button(
                icon: isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: isFullScreen ? "Exit full screen" : "Full screen",
                action: onToggleFullScreen
            )
        }
        .padding(10)
    }

    private func button(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                // 44pt target behind a smaller glyph — these sit in a corner
                // over video, where an undersized tap area is most annoying.
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .accessibilityLabel(label)
    }
}

/// Live video filling the whole screen.
///
/// Deliberately re-uses the same `stageManager`, so the cover attaches the
/// already-running preview views rather than joining the stage a second time —
/// going full screen mustn't cost a reconnect or a second viewer count.
private struct LiveFullScreenView: View {
    @ObservedObject var stageManager: IVSViewerStageManager
    let isJoining: Bool
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LiveViewerContent(stageManager: stageManager, isJoining: isJoining)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    LivePlaybackControls(
                        stageManager: stageManager,
                        isFullScreen: true,
                        onToggleFullScreen: onClose
                    )
                }
            }
        }
        // Portrait, because the app is portrait-only (project.yml:138) and
        // that can't be widened for one screen — UISupportedInterfaceOrientations
        // is what the app supports, and runtime can only narrow it. That is a
        // smaller loss than it sounds: hosts broadcast 9:16 from a phone, and a
        // portrait frame fitted into the inline 16:9 tile is pillarboxed down to
        // a strip, so filling the screen in portrait is exactly where the gain
        // is. Landscape for 16:9 broadcasts needs the plist widened plus every
        // other screen pinned to portrait in the app delegate — worth doing,
        // but not as a one-line change.
        .statusBarHidden()
    }
}

/// plays regardless of layout (IVS mixes it automatically), so this only
/// decides what you see.
private struct LiveViewerContent: View {
    @ObservedObject var stageManager: IVSViewerStageManager
    let isJoining: Bool
    /// Set once the grace period for a publisher to appear has elapsed.
    @State private var waitedTooLong = false

    /// Sorted so the slot order is stable between redraws — `remoteVideoViews`
    /// is a dictionary, so iterating it directly would let participants swap
    /// places whenever the dictionary rehashes.
    private var participantIDs: [String] {
        stageManager.remoteVideoViews.keys.sorted()
    }

    /// 1 guest fills the frame; 2–4 go two-up; 5+ go three-up. Kept to whole
    /// columns so no row is left with a single stretched tile.
    private var columnCount: Int {
        switch participantIDs.count {
        case 0, 1: return 1
        case 2...4: return 2
        default: return 3
        }
    }

    var body: some View {
        if !participantIDs.isEmpty {
            GeometryReader { geo in
                let columns = columnCount
                let rows = Int(ceil(Double(participantIDs.count) / Double(columns)))
                let tileWidth = geo.size.width / Double(columns)
                let tileHeight = geo.size.height / Double(max(rows, 1))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                    spacing: 2
                ) {
                    ForEach(participantIDs, id: \.self) { id in
                        if let view = stageManager.remoteVideoViews[id] {
                            CameraPreviewView(previewView: view)
                                .frame(width: tileWidth - 2, height: tileHeight - 2)
                                .clipped()
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        } else if stageManager.remoteParticipantLeft {
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 28))
                Text("This live stream has ended. The replay will be available shortly.")
                    .font(StreamrFont.caption())
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 24)
        } else if waitedTooLong {
            // A stream marked Live whose host never actually connected — or
            // whose broadcast died without the server being told — has no
            // publisher and never will, so the spinner below would turn
            // forever. Reported 2026-10-11 with a screenshot of this screen
            // stuck on "Connecting…" against a stream that had been dead for
            // hours. Saying so is more honest than an animation that implies
            // something is still on its way.
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 28))
                Text("Nobody is broadcasting to this stream right now.")
                    .font(StreamrFont.caption())
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 24)
        } else {
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(isJoining || stageManager.connectionState == .connecting ? "Connecting…" : "Waiting for video…")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.75))
            }
            // Restarted whenever the connection state changes, so a genuine
            // reconnect gets the full grace period again rather than inheriting
            // an almost-expired one.
            .task(id: stageManager.connectionState) {
                waitedTooLong = false
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { return }
                waitedTooLong = true
            }
        }
    }
}
