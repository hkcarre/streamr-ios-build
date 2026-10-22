import Foundation
import Combine

/// Who this device's owner has chosen not to see.
///
/// Exists because App Store Review Guideline 1.2 requires any app hosting
/// user-generated content to offer "the ability to block abusive users", a
/// mechanism to report offensive content, and published contact details.
/// Streamr hosts live broadcasts, replays and live chat, so 1.2 applies and a
/// build without this is rejected on sight — it was one of three open App
/// Store blockers as of 2026-10-22.
///
/// **Deliberately local.** There is no block or report endpoint on the backend
/// (confirmed against the live API 2026-10-22: nothing under `/user/block`,
/// `/report` or similar, and the whole surface is catalogued in
/// Endpoint.swift). A block therefore means "hide this from me on this
/// device", which is what the guideline asks for from the app's side. When the
/// backend grows a real block list, this type is the single place that has to
/// start talking to it — every screen asks `isBlocked` rather than keeping its
/// own copy.
///
/// Two kinds of key, because the two content surfaces identify people
/// differently:
///
/// - **Episodes** carry a real owner id (`StreamItem.ownerId`,
///   `StreamDetail.userId?.id`), so those block by id and are exact.
/// - **Chat** historically carried only a display name: the web app puts
///   `userName`/`userImage` in the IVS message attributes and nothing else, and
///   this client matched those keys so messages render identically on both.
///   `IVSChatManager` now also sends `userId`, so iOS-sent messages block
///   exactly; a message from the website still has only a name to go on.
///
/// Blocking by name is weaker — two viewers can choose the same display name —
/// so it is a fallback, never the preferred key, and the UI says which one it
/// used.
@MainActor
final class ModerationStore: ObservableObject {
    /// One blocked person, with enough detail for the management screen to
    /// show a name rather than an opaque id.
    struct BlockedAccount: Codable, Identifiable, Equatable {
        /// `id:<userId>` or `name:<displayName>` — see `Key`.
        let id: String
        let displayName: String
        let blockedAt: Date

        var isNameOnly: Bool { id.hasPrefix("name:") }
    }

    /// How a person is identified in a block entry.
    enum Key: Equatable {
        case userId(String)
        case displayName(String)

        var storageKey: String {
            switch self {
            case .userId(let value): return "id:\(value)"
            case .displayName(let value): return "name:\(value.lowercased())"
            }
        }
    }

    @Published private(set) var blocked: [BlockedAccount] = []

    /// A set alongside the array purely so `isBlocked` is O(1) — it is called
    /// per chat message on a room that can run at several messages a second,
    /// and per row while filtering the discover lists.
    private var blockedKeys: Set<String> = []

    private let defaults: UserDefaults
    private let storageKey = "moderation.blockedAccounts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    func isBlocked(_ key: Key) -> Bool {
        blockedKeys.contains(key.storageKey)
    }

    /// Convenience for the common case: an episode whose owner id may be nil.
    /// A nil id is never blocked — refusing to show content because we could
    /// not identify its owner would hide the whole catalogue the first time
    /// the API omitted a field.
    func isBlocked(userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return isBlocked(.userId(userId))
    }

    /// Chat's two-key lookup: prefer the id, fall back to the name.
    func isBlockedSender(userId: String?, userName: String) -> Bool {
        if isBlocked(userId: userId) { return true }
        return isBlocked(.displayName(userName))
    }

    // MARK: - Mutations

    func block(_ key: Key, displayName: String) {
        let storage = key.storageKey
        guard !blockedKeys.contains(storage) else { return }
        blockedKeys.insert(storage)
        blocked.insert(
            BlockedAccount(
                id: storage,
                displayName: displayName.isEmpty ? "Unnamed account" : displayName,
                blockedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func unblock(_ account: BlockedAccount) {
        blockedKeys.remove(account.id)
        blocked.removeAll { $0.id == account.id }
        persist()
    }

    func unblockAll() {
        blockedKeys.removeAll()
        blocked.removeAll()
        persist()
    }

    // MARK: - Persistence

    /// UserDefaults rather than the keychain: a block list is a preference,
    /// not a credential, and KeychainStore is reserved for the session token.
    /// Losing it on reinstall is acceptable; leaking it is not a concern.
    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([BlockedAccount].self, from: data) else {
            // A shape change shouldn't strand someone with an unreadable list
            // they can't clear from the UI, so drop it and start clean.
            defaults.removeObject(forKey: storageKey)
            return
        }
        blocked = decoded
        blockedKeys = Set(decoded.map(\.id))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(blocked) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
