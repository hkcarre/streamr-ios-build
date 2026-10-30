import Foundation

/// Backs the wireframe's "Alert Me" feature on Show Detail — confirmed live
/// 2026-09-28 (GET /user/toggle, POST /user/toggle-alert). showId/creatorId
/// are mutually exclusive server-side (see AlertType's doc comment).
@MainActor
final class AlertMeViewModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var activeType: AlertType?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let userId: String
    private let creatorId: String
    private let showId: String

    init(userId: String, creatorId: String, showId: String) {
        self.userId = userId
        self.creatorId = creatorId
        self.showId = showId
    }

    func load() async {
        do {
            let details = try await APIClient.shared.request(
                API.User.alertDetails(creatorId: creatorId, showId: showId), as: AlertDetails.self
            )
            apply(details)
        } catch {
            // Best-effort — the button just starts in its "Alert me" (off)
            // default state if this fails.
        }
    }

    func toggle(_ type: AlertType) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let details = try await APIClient.shared.request(
                API.User.toggleAlert(userId: userId, creatorId: creatorId, showId: showId, alertType: type),
                as: AlertDetails.self
            )
            apply(details)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ details: AlertDetails) {
        isActive = details.isActive
        activeType = details.alertType.flatMap(AlertType.init(rawValue:))
    }
}
