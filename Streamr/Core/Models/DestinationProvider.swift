import Foundation

/// The real OAuth-connectable providers, confirmed against orca-nebula's
/// SocialMedia.tsx (`renderPlatform` calls). Vimeo is declared in that repo's
/// validator enum but never actually wired to a connect row — left out here
/// until it's real on the website too.
enum DestinationProvider: String, CaseIterable, Identifiable {
    case youtube
    case facebook
    case dailymotion
    case twitch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        case .dailymotion: "Dailymotion"
        case .twitch: "Twitch"
        }
    }

    var iconAssetName: String {
        switch self {
        case .youtube: "DestinationYouTube"
        case .facebook: "DestinationFacebook"
        case .dailymotion: "DestinationDailymotion"
        case .twitch: "DestinationTwitch"
        }
    }
}

/// RSS-feed-based platforms — not OAuth-connectable on the website either,
/// shown as static, non-interactive badges. No Amazon Music entry: no source
/// asset exists in orca-nebula's public/images, and it isn't wired up there.
enum DestinationBadge: String, CaseIterable, Identifiable {
    case applePodcasts
    case spotify
    case iHeartRadio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applePodcasts: "Apple Podcasts"
        case .spotify: "Spotify"
        case .iHeartRadio: "iHeartRadio"
        }
    }

    var iconAssetName: String {
        switch self {
        case .applePodcasts: "DestinationApplePodcasts"
        case .spotify: "DestinationSpotify"
        case .iHeartRadio: "DestinationIHeartRadio"
        }
    }
}
