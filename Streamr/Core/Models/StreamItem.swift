import Foundation

/// Mirrors orca-nebula's `StreamItem` type — the live/VOD content unit.
/// `status` is the key state machine the iOS app needs to render correctly
/// (live badge vs. scheduled countdown vs. VOD playback).
struct StreamItem: Codable, Identifiable, Equatable {
    /// A plain `String: Codable` enum throws on any raw value it doesn't
    /// recognize, even though `status` itself is Optional — Optional only
    /// covers a *missing* key, not an unparseable one. Confirmed live
    /// 2026-09-02: `create-stage`'s response includes `"status":"Created"`,
    /// a real value this enum never had a case for, which threw and failed
    /// the whole `StreamItem` decode — silently blocking the Add Stream
    /// wizard from ever getting a stream id back (surfaced to the user as
    /// the backend's own success message shown like an error, via
    /// APIClient's decode-failure-falls-back-to-response-message path).
    /// Custom decoding here makes any future/unseen status value fail open
    /// (`.unknown`) instead of failing the entire object.
    enum Status: String, Codable {
        case created = "Created"
        /// The lobby: the host is on the stage but hasn't pressed Start, so
        /// the countdown hasn't run and nothing is being broadcast yet
        /// (confirmed by the backend developer 2026-10-20 — the flow is
        /// Staging -> Start -> Countdown -> Live). Previously unmapped, so a
        /// stream in the lobby decoded as `.unknown`.
        case staging = "Staging"
        case live = "Live"
        case scheduled = "Scheduled"
        case fulfilled = "Fulfilled"
        case processing = "Processing"
        case expired = "Expired"
        case error = "Error"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    let id: String
    let title: String
    let description: String?
    let videoURL: String?
    let thumbnail: String?
    let status: Status?
    let scheduledTime: String?
    let createdAt: String?
    let durationSeconds: Int?
    let tags: [String]?
    /// Confirmed live 2026-09-02, present on create-stage's response for
    /// Stream/Record — this, not get-token, is the confirmed real source
    /// for the guest-invite link's stageArn (see AddStreamCoordinator).
    let stageArn: String?
    /// Confirmed live 2026-09-28 (create-stage and by-show-live-completed
    /// both include these as Ints) — needed to prefill Edit Episode's
    /// Season/Episode dropdowns with the current value.
    let season: Int?
    let episode: Int?
    /// Who the episode belongs to. The public list populates this as an object
    /// (`{_id, firstName, lastName}`), so it's decoded through Show's tolerant
    /// reference type rather than a plain String — see Show.OwnerReference for
    /// why that matters. Needed by LiveSessionMonitor to pick the signed-in
    /// user's own live stream out of the public list.
    let owner: Show.OwnerReference?
    /// `"stream"`, `"record"` or `"upload"` — the same field the public list
    /// filters on. Kept as a raw String rather than an enum so an unseen value
    /// can't fail the decode (same reasoning as Status's custom decoder).
    let type: String?
    /// View count, used to rank the landing carousel when nothing is live.
    /// Confirmed present on the public list payload 2026-10-11.
    let totalViews: Int?

    var ownerId: String? { owner?.id }

    /// A recording session rather than a public broadcast. Drives wording:
    /// telling someone they are "live" while they are recording was already
    /// reported as confusing once (2026-10-11, "says go live when should say
    /// recording").
    var isRecordingSession: Bool { type == "record" }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, description, videoURL, thumbnail, status, scheduledTime, createdAt, durationSeconds, tags
        case stageArn, season, episode
        case owner = "userId"
        case type, totalViews
    }

    var isLive: Bool { status == .live }

    /// A finished episode you can actually press play on — either a live
    /// stream that has ended and finished processing, or a straight upload.
    ///
    /// Keyed on `videoURL` being present rather than on a `status` value,
    /// because the status that means "done" differs by path (`Fulfilled` for a
    /// recorded broadcast, and an upload can arrive already complete) and
    /// `Processing` means the replay exists but isn't playable yet. A URL is
    /// the one condition that always means "there is something to watch".
    var isWatchableReplay: Bool {
        !isLive && !(videoURL ?? "").isEmpty
    }
}
