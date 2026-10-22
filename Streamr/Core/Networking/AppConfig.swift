import Foundation

enum AppConfigError: LocalizedError {
    case missingAPIBaseURL

    var errorDescription: String? {
        "APIBaseURL is missing or invalid in Info.plist — check Config/*.xcconfig"
    }
}

/// Reads the per-configuration values injected via Config/*.xcconfig + Info.plist,
/// mirroring the web apps' env-cmd Debug/Staging/Release split.
///
/// Throws instead of crashing on a bad/missing value — a placeholder or malformed
/// URL here shouldn't take down the whole app, just fail whatever request needed it
/// (which the DEBUG mock-data fallbacks in the view models already handle).
enum AppConfig {
    static func apiBaseURL() throws -> URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            let url = URL(string: raw)
        else {
            throw AppConfigError.missingAPIBaseURL
        }
        return url
    }

    static var environmentName: String {
        Bundle.main.object(forInfoDictionaryKey: "APIEnvironmentName") as? String ?? "Unknown"
    }
}
