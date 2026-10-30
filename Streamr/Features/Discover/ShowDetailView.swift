import SwiftUI

/// Reached by tapping a show in Main Stream's show list — the wireframe/
/// website both push into a per-show episode list from there, which had no
/// iOS equivalent before this (DiscoverView previously only ever linked
/// straight into a single episode's PlayerView). Header shows the show
/// itself; body is that show's real episode list via API.Streams.byShow,
/// each one opening the existing PlayerView.
struct ShowDetailView: View {
    let show: Show
    @StateObject private var viewModel: ShowDetailViewModel
    @EnvironmentObject private var authManager: AuthManager
    /// Plain @State, not @StateObject — only ever created once both a real
    /// userId (must be logged in) and the show's host id (only populated by
    /// the Main Stream list this screen is reached from, see Show's doc
    /// comments) are known, which isn't guaranteed at init time.
    @State private var alertViewModel: AlertMeViewModel?
    @State private var showingAlertSheet = false
    /// Shared with PlayerView via the same key — see `videoToggle`.
    @AppStorage(PlaybackPreference.prefersVideoKey) private var prefersVideo = true
    @State private var editingEpisode: StreamItem?
    @State private var deletingEpisode: StreamItem?
    @State private var replacingAudioEpisode: StreamItem?
    /// Awaiting confirmation before `/stream/end` is called on it.
    @State private var endingEpisode: StreamItem?
    /// The one currently in flight, so its button can show progress and the
    /// others stay disabled rather than letting two ends race.
    @State private var endingEpisodeId: String?

    init(show: Show) {
        self.show = show
        _viewModel = StateObject(wrappedValue: ShowDetailViewModel(showId: show.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // The error banner sits OUTSIDE the empty-state branch on
                // purpose. It used to render only inside `emptyState`, i.e.
                // only when `episodes.isEmpty` — but editing or deleting an
                // episode requires at least one to exist, so those failures
                // were unreachable by construction: the owner confirmed Delete,
                // the request failed, the row stayed, and nothing was said.
                if let errorMessage = viewModel.errorMessage, !viewModel.episodes.isEmpty {
                    errorBanner(errorMessage)
                }

                if viewModel.episodes.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.episodes.isEmpty {
                    emptyState
                } else {
                    episodeList
                }
            }
            .padding(20)
        }
        .streamrBackground()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task {
            await viewModel.loadInitial()
            await loadAlertStateIfPossible()
        }
        .sheet(isPresented: $showingAlertSheet) {
            if let alertViewModel {
                AlertMeSheet(viewModel: alertViewModel)
            }
        }
        .sheet(item: $editingEpisode) { episode in
            EditEpisodeView(episode: episode, viewModel: viewModel)
        }
        .sheet(item: $replacingAudioEpisode) { episode in
            ReplaceAudioView(streamId: episode.id)
        }
        .alert("Delete Existing Stream?", isPresented: Binding(
            get: { deletingEpisode != nil },
            set: { if !$0 { deletingEpisode = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingEpisode = nil }
            Button("Delete", role: .destructive) {
                if let deletingEpisode {
                    Task { _ = await viewModel.delete(deletingEpisode) }
                }
                deletingEpisode = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("End this stream?", isPresented: Binding(
            get: { endingEpisode != nil },
            set: { if !$0 { endingEpisode = nil } }
        )) {
            Button("Cancel", role: .cancel) { endingEpisode = nil }
            Button("End Stream", role: .destructive) {
                if let episode = endingEpisode {
                    endingEpisode = nil
                    Task {
                        endingEpisodeId = episode.id
                        _ = await viewModel.endLiveStream(episode)
                        endingEpisodeId = nil
                    }
                }
            }
        } message: {
            Text("This takes it off the home page and sends it to processing. Only do this if nobody is broadcasting — anyone still live will be cut off.")
        }
    }

    /// Edit/Delete are only ever offered on episodes belonging to the
    /// currently logged-in user — this screen also serves as the Main
    /// Stream "browse anyone's show" destination, where mutating someone
    /// else's episode should never be reachable.
    /// Either source of ownership counts. `host` is populated only by the Main
    /// Stream list, so keying on it alone meant the owner-only controls were
    /// missing on the My Stream path — the one list that contains nothing but
    /// your own shows. `ownerId` comes off the show document itself and covers
    /// that case (see Show.ownerId).
    private var isOwner: Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        return show.host?.id == userId || show.ownerId == userId
    }

    /// Guests, and shows reached from anywhere other than the Main Stream
    /// list (no host id), simply never get the button — no auth prompt,
    /// matching how Follow/Like/Share on PlayerView don't gate on auth
    /// either (this one genuinely can't work without both ids, unlike
    /// those local-only stubs).
    private func loadAlertStateIfPossible() async {
        guard let userId = authManager.currentUser?.id, let creatorId = show.host?.id else { return }
        let vm = AlertMeViewModel(userId: userId, creatorId: creatorId, showId: show.id)
        alertViewModel = vm
        await vm.load()
    }

    /// Reworked 2026-10-08 from `wireframes/video playlist page edits.png`,
    /// which flagged three things on this screen: the artwork was too large,
    /// the show info was overlapping it, and the audio/video toggle was
    /// missing.
    ///
    /// The overlap came from the cover art: it was a full-width 16:9 banner
    /// whose AsyncImage used `contentMode: .fill`, so a tall poster (which is
    /// what shows actually upload) overflowed its frame and ran under the
    /// title. `.clipped()` on the container is what actually stops that —
    /// `.clipShape` on the image alone didn't, because the overflowing content
    /// is laid out before it is masked.
    ///
    /// The artwork is now a fixed 120pt tile beside the title rather than a
    /// banner, matching the wireframe's small "Show Artwork" box.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                coverArt
                    .frame(width: 120, height: 120)
                    .background(StreamrColor.surfaceDark)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    // Belt and braces: stops any .fill content bleeding out of
                    // the tile and under the text beside it.
                    .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(show.name)
                        .font(StreamrFont.title(20))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let hostName = show.host?.displayName, !hostName.isEmpty {
                        Text(hostName)
                            .font(StreamrFont.body(14))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let alertViewModel {
                        AlertMeButton(viewModel: alertViewModel) {
                            showingAlertSheet = true
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }

            videoToggle

            if let description = show.description, !description.isEmpty {
                Text(description)
                    .font(StreamrFont.body(14))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var coverArt: some View {
        if let coverPic = show.coverPic, let url = URL(string: coverPic) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The "Video On" switch from the wireframe. Stored per-device rather than
    /// per-show — it's a playback preference ("play episodes with video, or
    /// audio only"), and `PlayerView` reads the same key, so turning it off
    /// here makes episodes open in audio-only mode. Audio-only is useful on
    /// cellular and for podcast-style listening with the screen off.
    private var videoToggle: some View {
        Toggle(isOn: $prefersVideo) {
            Text(prefersVideo ? "Video On" : "Audio Only")
                .font(StreamrFont.headline(14))
                .foregroundStyle(.white)
        }
        .toggleStyle(SwitchToggleStyle(tint: StreamrColor.primary))
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var episodeList: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.episodes) { episode in
                VStack(spacing: 8) {
                    // Value-based, not a destination closure — see StreamRoute
                    // for why the closure form left the episode you'd just
                    // backed out of unable to reopen.
                    NavigationLink(value: PlayerRoute(streamId: episode.id)) {
                        StreamCardView(stream: episode)
                    }
                    .buttonStyle(.plain)

                    // Shown inline rather than only in the long-press menu: a
                    // stream stuck Live is a problem the owner needs to be able
                    // to SEE they can fix, and a hidden context menu doesn't
                    // tell anyone it exists.
                    if isOwner, episode.isLive {
                        endLiveRow(episode)
                    }
                }
                .task { await viewModel.loadMoreIfNeeded(currentItem: episode) }
                // .contextMenu (long-press), not .swipeActions — this
                // screen is a ScrollView/LazyVStack, not a List, and
                // swipeActions only works inside a List.
                .contextMenu {
                    if isOwner {
                        if episode.isLive {
                            Button(role: .destructive) {
                                endingEpisode = episode
                            } label: {
                                Label("End Stream Now", systemImage: "stop.circle")
                            }
                        }
                        Button {
                            editingEpisode = episode
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            replacingAudioEpisode = episode
                        } label: {
                            Label("Replace Audio (RSS Only)", systemImage: "waveform.badge.plus")
                        }
                        Button(role: .destructive) {
                            deletingEpisode = episode
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// The owner's way out of a stream that is stuck Live.
    ///
    /// Says plainly what the situation is, because the common case isn't "you
    /// forgot to stop" — it's a session that already ended badly and left the
    /// record behind, which from the outside just looks like the app lying
    /// about being on air.
    private func endLiveRow(_ episode: StreamItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StreamrColor.liveRed)

            Text("Still marked live. If you're not broadcasting, end it to clear it from the home page.")
                .font(StreamrFont.caption(12))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                endingEpisode = episode
            } label: {
                Text(endingEpisodeId == episode.id ? "Ending…" : "End")
                    .font(StreamrFont.headline(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(StreamrColor.liveRed)
                    .clipShape(Capsule())
            }
            .disabled(endingEpisodeId != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Dismissible, because an error about one failed action shouldn't stay
    /// pinned over the list for the rest of the session.
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StreamrColor.warningGold)
            Text(message)
                .font(StreamrFont.caption())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(.leading, 12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(viewModel.errorMessage ?? "No episodes yet.")
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// A dedicated @ObservedObject-backed subview, not a plain function on
/// ShowDetailView — ShowDetailView only holds `alertViewModel` as a plain
/// @State reference (its identity, not its @Published internals), so a
/// function returning inline View content wouldn't re-render when
/// AlertMeViewModel.isActive changes after a toggle in the sheet. This
/// subview observing it directly is what makes that update actually show.
private struct AlertMeButton: View {
    @ObservedObject var viewModel: AlertMeViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                viewModel.isActive ? "Notifications On" : "Alert me",
                systemImage: viewModel.isActive ? "bell.fill" : "bell"
            )
            .font(StreamrFont.caption(12))
            .foregroundStyle(viewModel.isActive ? .black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isActive ? StreamrColor.primary : Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .fixedSize()
    }
}
