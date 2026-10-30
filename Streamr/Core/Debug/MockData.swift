#if DEBUG
import Foundation

/// Sample data used only in Debug builds so the app is browsable — via the
/// "Continue with Demo Data" button, and as a network-failure fallback — before
/// a real backend URL is wired up. None of this compiles into Release builds.
enum MockData {
    /// True when the UI test harness asked for deterministic public content.
    ///
    /// Every other mock fallback in this app fires only when the network
    /// *fails*. In CI the network works fine, so the Main Stream carousels
    /// render whatever happens to be on production that morning — which is how
    /// two junk uploads ("Test audio test" / "The sky is purple") ended up in
    /// the screenshots that were about to go on the App Store listing
    /// (2026-10-30). Store screenshots have to be reproducible, and they can't
    /// be hostage to someone else's test upload.
    ///
    /// Opt-in via launch argument, so a normal Debug build on a device still
    /// talks to the real API and this changes nothing for anyone but the tests.
    static let useMockDiscovery =
        ProcessInfo.processInfo.arguments.contains("-StreamrUseMockDiscovery")

    static let user = User(
        id: "demo-user-1",
        firstName: "Alex",
        lastName: "Rivera",
        email: "alex@streamr.demo",
        profilePic: nil,
        accountType: "creator",
        role: "User",
        isEmailVerified: true,
        status: "Active",
        token: "demo-token"
    )

    static let streams: [StreamItem] = [
        StreamItem(
            id: "s1", title: "Friday Night Jam",
            description: "Live acoustic set from the studio.",
            videoURL: nil, thumbnail: nil, status: .live,
            scheduledTime: nil, createdAt: nil, durationSeconds: nil,
            tags: ["music", "live"], stageArn: nil, season: 1, episode: 1, owner: nil, type: "stream", totalViews: 120
        ),
        StreamItem(
            id: "s2", title: "Tech Talk: SwiftUI Tips",
            description: "Weekly dev show, recorded.",
            // Apple's own public sample HLS stream. Every mock stream had
            // `videoURL: nil`, which meant demo mode could never reach the
            // player's actual playback path — no video surface, no full
            // screen, no PIP, and no audio-only transport controls, since all
            // four require a real asset. A finished episode with nothing to
            // play also made `isWatchableReplay` false everywhere, so the
            // Recently Finished section was invisible in demo mode and in CI
            // screenshots. DEBUG-only, so no external URL ships in a release.
            videoURL: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
            thumbnail: nil, status: .fulfilled,
            scheduledTime: nil, createdAt: nil, durationSeconds: 1830,
            tags: ["tech"], stageArn: nil, season: 1, episode: 2, owner: nil, type: "stream", totalViews: 120
        ),
        StreamItem(
            id: "s3", title: "Sunday Morning Coffee Chat",
            description: "Scheduled community hangout.",
            videoURL: nil, thumbnail: nil, status: .scheduled,
            scheduledTime: "2026-08-10T14:00:00Z", createdAt: nil, durationSeconds: nil,
            tags: ["community"], stageArn: nil, season: 1, episode: 3, owner: nil, type: "stream", totalViews: 120
        )
    ]

    static let categories: [Category] = [
        Category(id: "cat1", name: "Music", status: "Active"),
        Category(id: "cat2", name: "Technology", status: "Active"),
        Category(id: "cat3", name: "Comedy", status: "Active"),
        Category(id: "cat4", name: "News & Politics", status: "Active")
    ]

    static let shows: [Show] = [
        Show(
            id: "show1", name: "The Alex Rivera Show",
            description: "Music, tech, and conversation.",
            coverPic: nil, autoSharing: true, createdAt: nil, updatedAt: nil
        ),
        Show(
            id: "show2", name: "Late Night Coding",
            description: "Building in public, every week.",
            coverPic: nil, autoSharing: false, createdAt: nil, updatedAt: nil
        )
    ]

    /// Deliberately separate from `shows` above, with different names —
    /// `shows` is also what the Add Stream wizard's demo-mode show picker
    /// displays, and reusing it here made "The Alex Rivera Show" ambiguous
    /// on screen at once (Main Stream's own fallback + the wizard's picker),
    /// breaking ScreenshotTests' lookup of it there (confirmed 2026-09-03).
    static let mainStreamShows: [Show] = [
        Show(
            id: "mainshow1", name: "Weekend Wanderlust",
            description: "Travel stories from around the world.",
            coverPic: nil, autoSharing: true, createdAt: nil, updatedAt: nil,
            host: Show.Host(id: "host1", firstName: "Jordan", lastName: "Lee", profilePic: nil)
        ),
        Show(
            id: "mainshow2", name: "The Night Owl Hour",
            description: "Late-night conversations with night-shift creators.",
            coverPic: nil, autoSharing: false, createdAt: nil, updatedAt: nil,
            host: Show.Host(id: "host2", firstName: "Sam", lastName: "Torres", profilePic: nil)
        )
    ]

    static let connectedAccounts: [ConnectedAccount] = [
        ConnectedAccount(provider: "youtube", status: "connected"),
        ConnectedAccount(provider: "facebook", status: "disconnected"),
        ConnectedAccount(provider: "dailymotion", status: "disconnected"),
        ConnectedAccount(provider: "twitch", status: "disconnected")
    ]

    static func streamDetail(id: String) -> StreamDetail {
        let json = """
        {
            "_id": "\(id)",
            "title": "Friday Night Jam",
            "description": "Live acoustic set from the studio.",
            "tags": ["music", "live"],
            "status": "Streaming Now",
            "scheduledTime": null,
            "videoURL": null,
            "format": "Video",
            "showId": {"_id": "show1", "name": "The Alex Rivera Show", "coverPic": null},
            "userId": {"_id": "demo-user-1", "firstName": "Alex", "lastName": "Rivera"}
        }
        """
        return try! JSONDecoder().decode(StreamDetail.self, from: Data(json.utf8))
    }
}
#endif
