import AVFoundation
import AVKit
import SwiftUI

/// Replaces SwiftUI's `VideoPlayer` for episode playback.
///
/// `VideoPlayer` renders AVKit's controls but exposes none of its
/// configuration, so three things the player needed were simply unreachable
/// from it — all three reported 2026-10-11 ("no full screen option on
/// playback; should default full screen for video; offer user PIP/navigation
/// in phone while video continues to play"):
///
///   - **Full screen.** There was no expand control at all, and no way to ask
///     for one. `entersFullScreenWhenPlaybackBegins` makes video go full screen
///     on play, and AVKit's own expand/minimise control handles the rest.
///   - **Picture in Picture.** Requires `allowsPictureInPicturePlayback`, plus
///     `canStartPictureInPictureAutomaticallyFromInline` so it kicks in when
///     you leave the screen rather than only on an explicit tap.
///   - **Aspect.** `.resizeAspect` letterboxes rather than cropping, so a
///     portrait episode keeps its full frame.
///
/// PIP and continued audio also need the `audio` background mode (declared in
/// project.yml) and an active `.playback` audio session — see
/// `configureForPlayback()`.
struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Video goes full screen as soon as it starts; audio-only deliberately
    /// does not. Full screen on an audio episode would be a black rectangle
    /// with a scrubber, which is why its author asked for video only ("do not
    /// need full screen for audio").
    let entersFullScreenOnPlay: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = entersFullScreenOnPlay
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.videoGravity = .resizeAspect
        // Populates the lock screen / Control Center transport, which is what
        // makes playback continue usefully once the app is backgrounded.
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.entersFullScreenWhenPlaybackBegins = entersFullScreenOnPlay
    }
}

extension AVAudioSession {
    /// Puts the session in `.playback` so episode audio keeps going in Picture
    /// in Picture and in the background, and isn't silenced by the ring/silent
    /// switch — the default `.soloAmbient` category does the opposite of all
    /// three, which would make "keep playing while I navigate the phone"
    /// impossible however the player itself is configured.
    ///
    /// Failures are swallowed on purpose: a session that won't activate must
    /// not stop an episode from playing at all, it just means audio won't
    /// survive backgrounding.
    static func configureForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
}
