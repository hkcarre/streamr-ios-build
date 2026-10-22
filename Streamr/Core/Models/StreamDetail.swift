import Foundation

/// `GET /stream/viewer/details/:id` response shape — reconstructed from how
/// orca-nebula's real player source destructures the payload
/// (`creator?.showId?.name`, `creator?.userId?.firstName`, `stream?.videoURL`,
/// SingleLive.tsx/SingleStream.tsx/services/viewerStream.ts), not from a live
/// call — same standing "verify before fully trusting" caveat as
/// StageTokenResponse/GenerateVideoURLResponse in Endpoint.swift.
struct StreamDetail: Decodable, Identifiable {
    struct ShowSummary: Decodable {
        let id: String
        let name: String?
        let coverPic: String?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case name, coverPic
        }
    }

    struct HostSummary: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case firstName, lastName
        }

        var displayName: String {
            [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        }
    }

    let id: String
    let title: String?
    let description: String?
    let tags: [String]?
    /// Kept as the raw string (not StreamItem.Status) — SingleLive.tsx
    /// branches on `status !== "Ended"` / `=== "Scheduled"` as literal
    /// strings, and "Ended" isn't one of StreamItem.Status's known cases.
    /// Forcing this through that enum would risk the whole detail decode
    /// failing on a real response over one unmapped case.
    let status: String?
    let scheduledTime: String?
    let videoURL: String?
    let format: StreamFormat?
    let showId: ShowSummary?
    let userId: HostSummary?
    /// Confirmed live 2026-10-04 against a disposable test "stream"-type
    /// episode: unlike the web app (which reads stageArn from URL query
    /// params passed in by whichever screen linked here, never from this
    /// endpoint), this endpoint DOES return stageArn directly — simpler for
    /// iOS, no need to plumb it through navigation from Main Stream/Show
    /// Detail. nil for "upload"/"record"-type episodes, which never get an
    /// IVS stage. See IVSViewerStageManager / API.Streams.viewerToken.
    let stageArn: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, description, tags, status, scheduledTime, videoURL, format, showId, userId, stageArn
    }

    var coverPicURLString: String? { showId?.coverPic }

    /// The replay URL, forced onto HTTPS.
    ///
    /// Finished episodes now come back pointing at a proxy on the API —
    /// `http://api.streamr.nyc/v1/stream/watch/{id}/{token}` — and that is
    /// **cleartext http**. The app declares no App Transport Security
    /// exception (deliberately: one would be an App Store review question and
    /// a real downgrade), so iOS refuses to load it and playback fails before
    /// a single byte moves. The server answers the same path over https
    /// perfectly well — verified 2026-10-14, HTTP 206 with `accept-ranges:
    /// bytes` — and plain http 301-redirects there anyway, which does the app
    /// no good because ATS blocks the first request before any redirect.
    ///
    /// Upgrading the scheme here rather than weakening ATS. The right place to
    /// fix it is the backend handing out an https URL; this makes playback work
    /// until it does.
    var playbackURL: URL? {
        guard let videoURL, !videoURL.isEmpty else { return nil }
        guard var components = URLComponents(string: videoURL) else { return nil }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    /// Named against the statuses the backend actually uses, rather than
    /// "anything that isn't Ended or Scheduled".
    ///
    /// The old definition made every finished episode `isLive` — a replay has
    /// status `Fulfilled`, which is neither Ended nor Scheduled — so the player
    /// put a red "Streaming Now" badge on completed episodes. Playback itself
    /// was saved only by a finished episode having no `stageArn`.
    ///
    /// `Staging` is the lobby before a broadcast starts: the host is on the
    /// stage but has not pressed Start, and the countdown hasn't run
    /// (confirmed by the backend developer, 2026-10-20 —
    /// Staging -> Start -> Countdown -> Live). Treating it as live made the
    /// player try to watch a broadcast that had not begun.
    var isLive: Bool { status == "Live" }
    var isStaging: Bool { status == "Staging" }
    var isScheduled: Bool { status == "Scheduled" }
    var isEnded: Bool { status == "Ended" || status == "Fulfilled" }
    var isProcessing: Bool { status == "Processing" }

    var statusLabel: String {
        if isLive { return "Streaming Now" }
        if isStaging { return "Starting soon" }
        if isScheduled { return "Scheduled" }
        if isProcessing { return "Processing" }
        if isEnded { return "Replay" }
        return status ?? ""
    }

    /// Best-effort public web link for the native share sheet — mirrors the
    /// route WatchLive.tsx itself links to for live entries
    /// (`/WatchLive/SingleLive/:id`); VOD/replay entries use the sibling
    /// `/WatchLive/SingleStream/:id` route (SingleStream.tsx). Not confirmed
    /// against a real deployed episode, since that would mean sharing a real
    /// stream publicly — verify the exact path before relying on it working
    /// end to end.
    var shareURL: URL? {
        let routeName = isEnded ? "SingleStream" : "SingleLive"
        return URL(string: "https://streamr.nyc/WatchLive/\(routeName)/\(id)")
    }
}
