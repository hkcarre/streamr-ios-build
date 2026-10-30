import Foundation
import Security

/// Stores the session JWT in the Keychain instead of UserDefaults/localStorage
/// (the web apps use localStorage; Keychain is the correct native equivalent).
enum KeychainStore {
    private static let service = "nyc.streamr.streamr.auth"
    private static let tokenAccount = "authToken"
    private static let userAccount = "currentUser"

    static func saveToken(_ token: String) {
        save(Data(token.utf8), account: tokenAccount)
    }

    static func loadToken() -> String? {
        guard let data = load(account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        delete(account: tokenAccount)
    }

    /// The signed-in user's own profile, cached alongside the token.
    ///
    /// Without this, a relaunch restored the token but left `currentUser` nil,
    /// so the app was authenticated with no idea who it was authenticated as.
    /// Every piece of UI keyed on the user — the hamburger header, the My
    /// Account profile block, the tab bar avatar — rendered its signed-out
    /// state. That's what "offers login while already logged in" was
    /// (reported 2026-10-11): not an auth bug, a missing-identity bug.
    ///
    /// Lives in the Keychain rather than UserDefaults because `User.token`
    /// carries the session JWT, so this is credential material and gets the
    /// same protection as the token itself.
    ///
    /// This is a cache, not the source of truth: a profile edited on the
    /// website won't appear here until the next login. The right fix is to
    /// re-fetch the profile on launch, which needs a confirmed
    /// "current user" endpoint — every `/user/*` path answers 401 before
    /// route matching, so one couldn't be identified without a live token
    /// (probed 2026-10-11).
    static func saveUser(_ user: User) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        save(data, account: userAccount)
    }

    static func loadUser() -> User? {
        guard let data = load(account: userAccount) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    static func deleteUser() {
        delete(account: userAccount)
    }

    // MARK: - Primitives

    private static func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // Found during a security audit: no kSecAttrAccessible was ever
        // set, leaving this on Apple's undocumented default rather than a
        // deliberate choice. AfterFirstUnlockThisDeviceOnly is the right
        // one for a session token specifically — stays available for
        // background refresh after the device has been unlocked once
        // (unlike WhenUnlocked, which would drop access while locked), but
        // ThisDeviceOnly excludes it from iCloud Keychain sync and
        // encrypted device-to-device backups, so a session token never
        // silently migrates to another device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
