import AVFoundation
import SwiftUI

/// Play/pause, elapsed/remaining time and a scrubber for audio-only playback.
///
/// Exists because turning the show page's "Video On" switch off left an episode
/// with **no way to start it** — reported 2026-10-11: "Audio Only > select
/// episode > does not give option to start the (audio) clip". In audio-only
/// mode `PlayerView` swapped the video surface for the cover art, and since
/// every transport control belonged to the video view, swapping it out took the
/// play button with it. The episode loaded, sat at 0:00, and offered nothing to
/// press.
///
/// Drives an `AVPlayer` directly rather than going through AVKit, because the
/// whole point of audio-only mode is that AVKit's video surface isn't on
/// screen.
struct AudioTransportView: View {
    let player: AVPlayer

    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    /// True while the user is dragging, so the observer's ticks don't fight the
    /// thumb for control of the slider.
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                Button {
                    seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22, weight: .medium))
                }
                .accessibilityLabel("Back 15 seconds")

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button {
                    seek(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 22, weight: .medium))
                }
                .accessibilityLabel("Forward 15 seconds")
            }
            .foregroundStyle(.white)

            if duration > 0 {
                Slider(
                    value: $currentTime,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { seek(to: currentTime) }
                    }
                )
                .tint(StreamrColor.primary)

                HStack {
                    Text(timeLabel(currentTime))
                    Spacer()
                    Text("-" + timeLabel(max(duration - currentTime, 0)))
                }
                .font(StreamrFont.caption(12))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .task { await prepare() }
        .onDisappear(perform: teardown)
    }

    // MARK: - Playback

    private func prepare() async {
        AVAudioSession.configureForPlayback()

        // Asked for asynchronously: a remote asset's duration isn't known at
        // init, and reading `.duration` synchronously would block.
        if let item = player.currentItem,
           let loaded = try? await item.asset.load(.duration) {
            let seconds = CMTimeGetSeconds(loaded)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite { currentTime = seconds }
            isPlaying = player.timeControlStatus == .playing
        }
    }

    /// The observer holds a strong reference to its closure, and the closure
    /// captures this view's state — leaving it attached would keep both alive
    /// for the lifetime of the player.
    private func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    private func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            AVAudioSession.configureForPlayback()
            player.play()
            isPlaying = true
        }
    }

    private func seek(by offset: Double) {
        var target = max(currentTime + offset, 0)
        // Only clamp to the end once the duration is actually known — it stays
        // 0 until the asset loads, and clamping to 0 would make skip-forward
        // jump to the start.
        if duration > 0 { target = min(target, duration) }
        seek(to: target)
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = seconds
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
