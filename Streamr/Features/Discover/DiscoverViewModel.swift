import Foundation

/// Drives the Main Stream screen's two independent sections: a live-only
/// carousel (empty when nothing's live — the screen reacts by hiding it
/// entirely, not showing an empty row) and a paginated, filterable show
/// list below it that's always visible. See DiscoverView's doc comment.
@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var liveStreams: [StreamItem] = []
    @Published private(set) var isLoadingLive = false

    /// Finished broadcasts and uploads, for the third section of the landing
    /// page — added 2026-10-11 to the ordering its author asked for: current
    /// streams first, then the latest shows, then finished/uploaded streams.
    @Published private(set) var finishedStreams: [StreamItem] = []

    @Published private(set) var shows: [Show] = []
    @Published private(set) var isLoadingShows = false
    @Published var errorMessage: String?

    @Published private(set) var categories: [Category] = []
    @Published var selectedCategoryId: String? {
        didSet { if oldValue != selectedCategoryId { Task { await refreshShows() } } }
    }
    @Published var isFuture = false {
        didSet { if oldValue != isFuture { Task { await refreshShows() } } }
    }

    /// Set by the view from the environment's ModerationStore. A closure
    /// rather than the store itself so this view model stays free of a
    /// dependency on a @MainActor ObservableObject it would also have to
    /// observe -- it only ever needs to ask a yes/no question, and nothing
    /// here should re-run when the block list changes (the view re-filters).
    var isBlockedOwner: (String?) -> Bool = { _ in false }

    private var currentPage = 1
    private var hasMorePages = true
    /// Bumped on every refreshShows() call so a slower, superseded fetch
    /// (e.g. category and Past/Future toggled in quick succession) can't
    /// land after a newer one and corrupt `shows`/`currentPage`.
    private var loadGeneration = 0

    func loadInitial() async {
        guard shows.isEmpty && liveStreams.isEmpty else { return }
        async let live: () = loadLiveStreams()
        async let cats: () = loadCategories()
        async let showsLoad: () = refreshShows()
        async let finished: () = loadFinishedStreams()
        _ = await (live, cats, showsLoad, finished)
    }

    func refresh() async {
        async let live: () = loadLiveStreams()
        async let showsLoad: () = refreshShows()
        async let finished: () = loadFinishedStreams()
        _ = await (live, showsLoad, finished)
    }

    func loadMoreShowsIfNeeded(currentItem: Show) async {
        guard hasMorePages, !isLoadingShows, currentItem.id == shows.last?.id else { return }
        await fetchNextShowsPage(generation: loadGeneration)
    }

    private func loadLiveStreams() async {
        isLoadingLive = true
        defer { isLoadingLive = false }
        do {
            let response = try await APIClient.shared.request(
                API.Discover.liveStreams(), as: APIResponse<[StreamItem]>.self
            )
            liveStreams = (response.data ?? []).filter { !isBlockedOwner($0.ownerId) }
        } catch {
            guard !error.isCancellation else { return }
            #if DEBUG
            liveStreams = MockData.streams.filter(\.isLive)
            #else
            // Best-effort: the show list below still works even if this
            // fails, so this just hides the carousel rather than surfacing
            // an error for the whole screen.
            liveStreams = []
            #endif
        }
    }

    /// Filtered client-side, not server-side — see
    /// `API.Discover.recentStreams` for why the "finished" filter value
    /// couldn't be confirmed against the live API.
    private func loadFinishedStreams() async {
        do {
            let response = try await APIClient.shared.request(
                API.Discover.recentStreams(), as: APIResponse<[StreamItem]>.self
            )
            finishedStreams = (response.data ?? [])
                .filter(\.isWatchableReplay)
                .filter { !isBlockedOwner($0.ownerId) }
        } catch {
            guard !error.isCancellation else { return }
            #if DEBUG
            finishedStreams = MockData.streams.filter(\.isWatchableReplay)
            #else
            // Best-effort, same as the live carousel: the section just hides.
            finishedStreams = []
            #endif
        }
    }

    private func loadCategories() async {
        do {
            let response = try await APIClient.shared.request(
                API.Discover.categories, as: APIResponse<[Category]>.self
            )
            categories = response.data ?? []
        } catch {
            // Best-effort — "All Categories" still works without this.
        }
    }

    private func refreshShows() async {
        loadGeneration += 1
        currentPage = 1
        hasMorePages = true
        shows = []
        await fetchNextShowsPage(generation: loadGeneration)
    }

    private func fetchNextShowsPage(generation: Int) async {
        isLoadingShows = true
        errorMessage = nil
        defer { isLoadingShows = false }

        do {
            let response = try await APIClient.shared.request(
                API.Shows.listWithCategory(
                    categoryId: selectedCategoryId ?? "", isFuture: isFuture, page: currentPage
                ),
                as: APIResponse<[Show]>.self
            )
            guard generation == loadGeneration else { return }
            let page = response.data ?? []
            shows.append(contentsOf: page)
            hasMorePages = !page.isEmpty
            currentPage += 1
        } catch {
            guard generation == loadGeneration else { return }
            // A cancelled refresh is not a failure — see Error.isCancellation.
            // Leaving `shows` as-is keeps whatever was already on screen.
            guard !error.isCancellation else { return }
            #if DEBUG
            if currentPage == 1 && shows.isEmpty && !isFuture {
                // MockData.mainStreamShows, not MockData.shows — that one is
                // also what the Add Stream wizard's demo-mode show picker
                // displays; reusing it here made "The Alex Rivera Show"
                // ambiguous on screen at once and broke ScreenshotTests'
                // lookup of it there (confirmed 2026-09-03 by a real CI
                // failure, not hypothetical).
                shows = MockData.mainStreamShows
                hasMorePages = false
                return
            }
            #endif
            errorMessage = error.localizedDescription
            hasMorePages = false
        }
    }
}
