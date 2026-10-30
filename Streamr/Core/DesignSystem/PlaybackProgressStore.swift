import Foundation

/// Remembers how far into each episode the viewer got, so leaving and coming
/// back resumes rather than restarting.
///
/// Before this, every open created a fresh `AVPlayer` at zero: backing out of a
/// 40-minute episode to check something and returning put you at the beginning,
/// with no way to get back except scrubbing. For a podcast-length format that
/// makes the player close to unusable, and it was the behaviour reported on
/// 2026-10-11 ("if they can stop and continue from the place they stopped").
///
/// `UserDefaults`, not the backend: there is no confirmed endpoint for playback
/// position, and inventing one would be a guess. The cost is that progress is
/// per-device and doesn't follow you to the website. Worth revisiting if the
/// backend grows a real resume-point API.
enum PlaybackProgressStore {
    private static let keyPrefix = "streamr.playback.position."

    /// Below this, resuming is more annoying than restarting — you haven't got
    /// anywhere yet and the jump feels like a glitch.
    private static let minimumResumeSeconds: Double = 15

    /// Within this of the end, the episode counts as watched: resuming would
    /// drop you onto the closing seconds, so start over instead.
    private static let endThresholdSeconds: Double = 30

    static func position(for streamId: String) -> Double? {
        let stored = UserDefaults.standard.double(forKey: keyPrefix + streamId)
        return stored >= minimumResumeSeconds ? stored : nil
    }

    /// Call on the way out. `duration` may be 0 when it isn't known yet, in
    /// which case the end-of-episode rule simply doesn't apply.
    static func save(_ seconds: Double, duration: Double, for streamId: String) {
        guard seconds.isFinite, seconds >= 0 else { return }

        let finished = duration > 0 && seconds >= duration - endThresholdSeconds
        if seconds < minimumResumeSeconds || finished {
            clear(for: streamId)
            return
        }
        UserDefaults.standard.set(seconds, forKey: keyPrefix + streamId)
    }

    static func clear(for streamId: String) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + streamId)
    }
}
