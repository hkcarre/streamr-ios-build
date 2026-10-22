import Foundation

@MainActor
final class ShowDetailViewModel: ObservableObject {
    @Published private(set) var episodes: [StreamItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let showId: String
    private var currentPage = 1
    private var hasMorePages = true

    init(showId: String) {
        self.showId = showId
    }

    func loadInitial() async {
        guard episodes.isEmpty else { return }
        await fetchNextPage()
    }

    func refresh() async {
        currentPage = 1
        hasMorePages = true
        episodes = []
        await fetchNextPage()
    }

    func loadMoreIfNeeded(currentItem: StreamItem) async {
        guard hasMorePages, !isLoading, currentItem.id == episodes.last?.id else { return }
        await fetchNextPage()
    }

    /// The edit endpoint's response only echoes back the fields it actually
    /// changed (title/description/season/episode/tags) — not status,
    /// videoURL, thumbnail, stageArn, etc. Replacing the local item with
    /// that sparse response directly would silently blank those out (e.g.
    /// a Live badge disappearing after an edit). Merges the known-changed
    /// fields onto the existing local item instead, via StreamItem's
    /// synthesized memberwise init (no custom init exists to block it).
    func update(episodeId: String, title: String, description: String, season: String, episode: String, tags: [String]) async -> Bool {
        errorMessage = nil
        do {
            _ = try await APIClient.shared.request(
                API.Streams.edit(id: episodeId, title: title, description: description, season: season, episode: episode, tags: tags),
                as: APIResponse<StreamItem>.self
            )
            if let index = episodes.firstIndex(where: { $0.id == episodeId }) {
                let old = episodes[index]
                episodes[index] = StreamItem(
                    id: old.id, title: title, description: description, videoURL: old.videoURL,
                    thumbnail: old.thumbnail, status: old.status, scheduledTime: old.scheduledTime,
                    createdAt: old.createdAt, durationSeconds: old.durationSeconds, tags: tags, stageArn: old.stageArn,
                    season: Int(season) ?? old.season, episode: Int(episode) ?? old.episode, owner: old.owner, type: old.type, totalViews: old.totalViews
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Ends an episode the server still believes is Live.
    ///
    /// A broadcast that didn't finish cleanly — the app force-quit, the network
    /// dropped, `/stream/end` refused — leaves the stream `Live` in the
    /// database with nothing actually publishing to it. It then sits in the
    /// public "Now Streaming" carousel indefinitely, visible to everyone,
    /// and reinstalling the app changes nothing because the stale state is
    /// server-side (reported 2026-10-11: "I still see in the homepage the
    /// streaming live", after deleting and reinstalling).
    ///
    /// Until now there was no way to clear one from the app at all: the only
    /// caller of `/stream/end` was the wizard's own staging screen, which is
    /// reachable only *during* the session that has already ended. So every
    /// orphan needed someone with database or website access, which is not a
    /// state a user should ever be stuck in.
    ///
    /// Deliberately ends rather than deletes. It's the same endpoint the Stop
    /// button calls, so the episode moves to Processing and can still publish
    /// — a recording that was interrupted keeps whatever it captured, where
    /// deleting would throw it away.
    func endLiveStream(_ episode: StreamItem) async -> Bool {
        errorMessage = nil
        do {
            let stageArn = try await resolveStageArn(for: episode)
            _ = try await APIClient.shared.request(
                API.Streams.endStream(stageArn: stageArn, streamId: episode.id),
                as: APIResponse<EmptyData>.self
            )
            markProcessing(episode.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `/stream/end` can't be called without a stage ARN, and the per-show
    /// episode list isn't guaranteed to carry one, so this falls back to the
    /// detail endpoint — which does return it directly (see
    /// StreamDetail.stageArn). Recovering from a stuck stream must not depend
    /// on which list happened to load the row.
    private func resolveStageArn(for episode: StreamItem) async throws -> String {
        if let arn = episode.stageArn, !arn.isEmpty { return arn }

        let response = try await APIClient.shared.request(
            API.Streams.viewerDetail(id: episode.id), as: APIResponse<StreamDetail>.self
        )
        guard let arn = response.data?.stageArn, !arn.isEmpty else {
            throw APIError.server(
                message: "This episode has no stage on record, so it can't be ended from the app. Send its id (\(episode.id)) to the team.",
                statusCode: 0
            )
        }
        return arn
    }

    /// Clears the Live badge locally so the row reflects the end immediately,
    /// without a refetch. Mirrors `update`'s merge approach — build a whole
    /// item from the old one rather than trusting the end response to echo
    /// every field back.
    private func markProcessing(_ episodeId: String) {
        guard let index = episodes.firstIndex(where: { $0.id == episodeId }) else { return }
        let old = episodes[index]
        episodes[index] = StreamItem(
            id: old.id, title: old.title, description: old.description, videoURL: old.videoURL,
            thumbnail: old.thumbnail, status: .processing, scheduledTime: old.scheduledTime,
            createdAt: old.createdAt, durationSeconds: old.durationSeconds, tags: old.tags,
            stageArn: old.stageArn, season: old.season, episode: old.episode, owner: old.owner, type: old.type, totalViews: old.totalViews
        )
    }

    func delete(_ episode: StreamItem) async -> Bool {
        errorMessage = nil
        do {
            _ = try await APIClient.shared.request(API.Streams.delete(id: episode.id), as: APIResponse<EmptyData>.self)
            episodes.removeAll { $0.id == episode.id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchNextPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.request(
                API.Streams.byShow(showId: showId, page: currentPage), as: APIResponse<[StreamItem]>.self
            )
            let page = response.data ?? []
            episodes.append(contentsOf: page)
            hasMorePages = !page.isEmpty
            currentPage += 1
        } catch {
            // A cancelled pull-to-refresh isn't a failure — see
            // Error.isCancellation.
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
            hasMorePages = false
        }
    }
}
