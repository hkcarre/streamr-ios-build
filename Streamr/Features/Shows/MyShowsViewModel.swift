import Foundation

@MainActor
final class MyShowsViewModel: ObservableObject {
    @Published private(set) var shows: [Show] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.request(
                API.Shows.mine(),
                as: APIResponse<[Show]>.self
            )
            shows = response.data ?? []
        } catch {
            // A cancelled pull-to-refresh isn't a failure — see
            // Error.isCancellation. Returning early also keeps the creator's
            // real shows on screen instead of replacing them with demo data
            // in DEBUG.
            guard !error.isCancellation else { return }
            #if DEBUG
            shows = MockData.shows
            #else
            errorMessage = error.localizedDescription
            #endif
        }
    }

    func upsert(_ show: Show) {
        if let index = shows.firstIndex(where: { $0.id == show.id }) {
            shows[index] = show
        } else {
            shows.insert(show, at: 0)
        }
    }

    func delete(_ show: Show) async {
        do {
            _ = try await APIClient.shared.request(
                API.Shows.delete(id: show.id), as: APIResponse<EmptyData>.self
            )
        } catch {
            #if DEBUG
            // Demo mode / offline — proceed with the local removal below regardless.
            #else
            errorMessage = error.localizedDescription
            return
            #endif
        }
        shows.removeAll { $0.id == show.id }
    }
}
