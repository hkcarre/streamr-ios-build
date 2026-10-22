import Foundation

/// What the carousel at the top of the landing page shows.
///
/// The rule, set 2026-10-14: three items. Anything live comes first and wins
/// outright. With nothing live, fall back to the best public episodes —
/// "top ones in terms of how new they are and how popular (views?)".
///
/// Kept out of the view so the ordering is one testable rule in one place
/// rather than something the landing page and the signed-out screen each
/// decide for themselves.
enum LandingCarousel {
    /// How many cards the strip carries.
    static let capacity = 3

    static func strip(
        live: [StreamItem],
        finished: [StreamItem]
    ) -> (title: String, streams: [StreamItem])? {
        if !live.isEmpty {
            return ("Now Streaming", Array(live.prefix(capacity)))
        }

        let ranked = topPicks(from: finished)
        if !ranked.isEmpty {
            return ("Popular Now", ranked)
        }

        return nil
    }

    /// Ranks on recency AND views together, rather than picking one.
    ///
    /// Sorting by views alone would freeze the same three episodes at the top
    /// forever — the ones with the longest head start — and a brand-new episode
    /// could never surface. Sorting by date alone ignores whether anyone
    /// actually watched. So each episode is scored on both, and the score for
    /// views is compressed with a logarithm: the jump from 10 views to 100
    /// matters, the jump from 1,000 to 1,090 does not.
    ///
    /// Recency is scored over a two-week window, after which an episode is
    /// carried on views alone. These weights are a starting point, not a
    /// tuned ranking — worth revisiting once there is enough real traffic to
    /// tell whether it surfaces the right things.
    static func topPicks(from streams: [StreamItem], now: Date = Date()) -> [StreamItem] {
        streams
            .map { (stream: $0, score: score(for: $0, now: now)) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.stream.id > rhs.stream.id }
                return lhs.score > rhs.score
            }
            .prefix(capacity)
            .map(\.stream)
    }

    private static func score(for stream: StreamItem, now: Date) -> Double {
        let views = Double(max(stream.totalViews ?? 0, 0))
        let popularity = log10(views + 1)

        // 1 for something posted right now, falling to 0 over two weeks. An
        // unparseable or missing date scores 0 rather than being dropped, so a
        // popular episode with a bad timestamp still appears.
        let freshness: Double
        if let createdAt = stream.createdAt, let date = ISO8601DateFormatter.streamr.date(from: createdAt) {
            let age = now.timeIntervalSince(date)
            let window: TimeInterval = 14 * 24 * 60 * 60
            freshness = max(0, 1 - (age / window))
        } else {
            freshness = 0
        }

        return popularity + freshness * 2
    }
}

extension ISO8601DateFormatter {
    /// The API's timestamps carry fractional seconds ("2026-10-11T13:19:54.475Z"),
    /// which the default configuration refuses outright.
    static let streamr: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
