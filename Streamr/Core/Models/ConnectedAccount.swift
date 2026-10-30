import Foundation

/// GET /user/connected/accounts response item — mirrors what
/// SocialMedia.tsx reads to decide each row's Connect/Disconnect state.
struct ConnectedAccount: Decodable {
    let provider: String
    let status: String?

    var isConnected: Bool { status == "connected" }
}
