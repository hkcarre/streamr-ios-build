import Foundation

struct Show: Codable, Identifiable, Equatable {
    struct Host: Codable, Equatable {
        let id: String
        let firstName: String?
        let lastName: String?
        let profilePic: String?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case firstName, lastName, profilePic
        }

        var displayName: String {
            [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    struct ScheduledSlot: Codable, Equatable {
        let scheduledTime: String?
    }

    /// A reference to the owning user that tolerates either shape `userId` can
    /// arrive in: the raw id string on an unpopulated show document, or an
    /// embedded user object if any endpoint ever populates the relation
    /// without renaming it.
    ///
    /// Decoded permissively on purpose. A plain `String?` here would throw on
    /// the object form, and because Codable failure is all-or-nothing that
    /// would fail the ENTIRE `Show` decode — taking out My Shows and the Main
    /// Stream show list over a field used for nothing but an ownership check.
    /// Same reasoning as StreamItem.Status's custom decoder, which this
    /// codebase added after exactly that class of break.
    struct OwnerReference: Codable, Equatable {
        let id: String?

        init(id: String?) {
            self.id = id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                id = raw
                return
            }
            id = (try? container.decode(Populated.self))?.id
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(id)
        }

        private struct Populated: Decodable {
            let id: String?

            enum CodingKeys: String, CodingKey {
                case id = "_id"
            }
        }
    }

    let id: String
    let name: String
    let description: String?
    let coverPic: String?
    let categoryId: String?
    let autoSharing: Bool?
    let createdAt: String?
    let updatedAt: String?
    /// Confirmed live 2026-09-02, only present from `/show/list-with-category`
    /// (the Main Stream show list) — nil for the plain `/show/list`
    /// (My Shows) and create/update responses, which don't embed it.
    let host: Host?
    /// Same source as `host` — nil outside the Main Stream list.
    let streamCount: Int?
    /// Only present when that list was queried with `isFutured: true`.
    let streamScheduledTime: [ScheduledSlot]?
    /// Per-show auto-share platform selection, distinct from `autoSharing`'s
    /// master on/off — confirmed live 2026-10-02 on /show/create,
    /// /show/update and /show/list. Raw values are DestinationProvider's
    /// ("youtube", "dailymotion", "twitch") plus the literal "RSS".
    let selectedProviders: [String]?
    /// The show's auto-generated podcast RSS feed URL — confirmed live
    /// 2026-10-02 as an empty string until the show's first stream exists,
    /// then a real streamr.nyc feed URL. See ReplaceAudioView, which updates
    /// this same feed's audio track.
    let rssLink: String?
    /// The owner's user id taken straight off the show document, as opposed to
    /// `host`, which is a populated user object only the Main Stream list
    /// embeds. Confirmed present on the show document live 2026-10-11 (it
    /// shows up as `showId.userId` on a populated stream payload).
    ///
    /// This is what lets ShowDetailView recognise the signed-in user as the
    /// owner when the screen was reached from My Stream — `host` is nil on that
    /// path, so owner-only controls were unreachable from the one list that is
    /// by definition nothing but your own shows.
    let owner: OwnerReference?

    /// The owner's id, whichever shape the field arrived in.
    var ownerId: String? { owner?.id }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, coverPic, categoryId, autoSharing, createdAt, updatedAt
        case host = "user"
        case streamCount, streamScheduledTime, selectedProviders, rssLink
        case owner = "userId"
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        coverPic: String? = nil,
        categoryId: String? = nil,
        autoSharing: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        host: Host? = nil,
        streamCount: Int? = nil,
        streamScheduledTime: [ScheduledSlot]? = nil,
        selectedProviders: [String]? = nil,
        rssLink: String? = nil,
        ownerId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.coverPic = coverPic
        self.categoryId = categoryId
        self.autoSharing = autoSharing
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.host = host
        self.streamCount = streamCount
        self.streamScheduledTime = streamScheduledTime
        self.selectedProviders = selectedProviders
        self.rssLink = rssLink
        self.owner = ownerId.map { OwnerReference(id: $0) }
    }
}
