import SwiftUI

/// Pure content — no NavigationStack/toolbar/background of its own. Embedded
/// by `StreamHomeView` as the "Main Stream" segment; that parent owns nav
/// chrome (title-less segmented toggle, hamburger, guest Log In button).
///
/// Three stacked sections, in the order the landing page's author asked for on
/// 2026-10-11 — "leftmost are the current streams, with the latest shows
/// visible, then after that latest streams finished/uploaded streams":
///
///   1. **Now Streaming** — what's live this moment, as a horizontal pane so
///      the current streams sit leftmost.
///   2. **Latest Shows** — the filterable show list.
///   3. **Recently Finished** — ended broadcasts and uploads you can replay.
///
/// Each loads independently (see DiscoverViewModel) and each hides entirely
/// when empty rather than rendering an empty row, so a quiet day collapses to
/// just the show list instead of two headings over nothing.
struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @EnvironmentObject private var moderation: ModerationStore
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Heads the page the way the wireframe's "Landing" screen does
                // — wordmark, then a strip of shows, then the rest. This is why
                // StreamHomeView drops the navigation-bar logo on this segment.
                LandingLogo()
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                // The landing strip always carries content when there is any to
                // carry. Live streams lead it, because current streams come
                // first — but a quiet day used to collapse the strip entirely
                // and leave the wordmark sitting on a filter row. When nothing
                // is live it falls back to finished episodes, which are still
                // something to watch.
                if let strip = landingStrip {
                    streamPane(title: strip.title, streams: strip.streams)
                }

                // The show list and its category filter are both behind
                // authentication — `/show/list-with-category` and
                // `/category/allCategory` each answer 401 without a token
                // (verified 2026-10-14). Signed out they can only ever fail, so
                // showing them meant an error message sitting where the
                // catalogue should be. Hidden instead, leaving the wordmark and
                // the carousel, which ARE public.
                if authManager.isAuthenticated {
                    filterRow

                    if viewModel.shows.isEmpty && viewModel.isLoadingShows {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if viewModel.shows.isEmpty {
                        emptyState
                    } else {
                        showList
                    }
                } else {
                    signedOutPrompt
                }

                // Skipped when the finished episodes were already promoted into
                // the landing strip above — the same list twice on one screen
                // reads as a rendering fault.
                if !viewModel.finishedStreams.isEmpty, !viewModel.liveStreams.isEmpty {
                    streamPane(
                        title: "Recently Finished",
                        streams: viewModel.finishedStreams
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable { await viewModel.refresh() }
        .task {
                // Hand the view model a way to ask the block list, before the
                // first fetch -- filtering on arrival rather than at render
                // time keeps a blocked creator out of pagination and out of
                // LandingCarousel's ranking, instead of leaving gaps in both.
                viewModel.isBlockedOwner = { moderation.isBlocked(userId: $0) }
                await viewModel.loadInitial()
            }
    }

    /// What the strip under the wordmark shows, and what it's called.
    ///
    /// Live first, because current streams lead the page. Falling back to
    /// finished episodes keeps the strip populated whenever the platform has
    /// anything at all to watch; nil only when it genuinely has nothing, where
    /// a heading over an empty row would be worse than no heading.
    private var landingStrip: (title: String, streams: [StreamItem])? {
        LandingCarousel.strip(live: viewModel.liveStreams, finished: viewModel.finishedStreams)
    }

    /// Shared by the landing strip and Recently Finished — same card, same
    /// horizontal pane, different source list. Now also shared with the
    /// signed-out account screen, which is why it lives in StreamStrip.
    private func streamPane(title: String, streams: [StreamItem]) -> some View {
        StreamStrip(title: title, streams: streams)
    }

    private var filterRow: some View {
        HStack(spacing: 12) {
            categoryMenu

            Spacer()

            Picker("", selection: $viewModel.isFuture) {
                Text("Past").tag(false)
                Text("Future").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 16)
    }

    private var categoryMenu: some View {
        Menu {
            Button("All Categories") { viewModel.selectedCategoryId = nil }
            ForEach(viewModel.categories) { category in
                Button(category.name) { viewModel.selectedCategoryId = category.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedCategoryName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
            }
            .font(StreamrFont.body(14))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryId = viewModel.selectedCategoryId else { return "All Categories" }
        return viewModel.categories.first { $0.id == selectedCategoryId }?.name ?? "All Categories"
    }

    private var showList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Shows")
                .font(StreamrFont.headline(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            LazyVStack(spacing: 12) {
                ForEach(viewModel.shows) { show in
                    // Value-based — see StreamRoute.
                    NavigationLink(value: ShowRoute(show: show)) {
                        MainStreamShowRowView(show: show, showScheduledTime: viewModel.isFuture)
                    }
                    .buttonStyle(.plain)
                    .task { await viewModel.loadMoreShowsIfNeeded(currentItem: show) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// What sits below the carousel when signed out. Says what logging in
    /// adds, rather than leaving the page looking like it finished loading
    /// half way.
    private var signedOutPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.5))
            Text("Log in to browse every show and follow the ones you like.")
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 32)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(viewModel.errorMessage ?? (viewModel.isFuture ? "No upcoming shows." : "No shows available."))
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }
}
