import Foundation

/// One place for the "Video On / Audio Only" preference key, so the show page
/// (which owns the switch, per `wireframes/video playlist page edits.png`) and
/// the player (which honours it) can't drift apart on a string literal.
///
/// Deliberately a per-device preference rather than per-show: it answers "how
/// do I want to listen right now" — on cellular, or with the screen off —
/// not "what is this show". That also means it survives navigating between
/// shows, which is what makes it useful.
enum PlaybackPreference {
    static let prefersVideoKey = "streamr.playback.prefersVideo"
}
