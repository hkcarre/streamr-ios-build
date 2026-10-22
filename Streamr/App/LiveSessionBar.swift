import SwiftUI

/// The one End control that is always there while you are broadcasting.
///
/// Sits directly above the tab bar on every screen, for as long as the
/// signed-in user has a stream that is live. That placement is the point: the
/// wizard's Stop button only exists while the broadcast sheet is open, so
/// dismissing it, taking a call, or relaunching the app left a host live with
/// no way to stop — "stream stuck in On position", and "end stream ... does not
/// appear during the live streaming event which is when it should appear"
/// (2026-10-14).
///
/// Red and pulsing on purpose. This is a state the user needs to know they are
/// in; it is the one place in the app allowed to be loud.
struct LiveSessionBar: View {
    @ObservedObject var monitor: LiveSessionMonitor
    @State private var showingConfirmation = false
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Recording and broadcasting are different acts, and the bar says which.
    /// Telling someone they are "live" while they are recording was already
    /// reported as confusing once (2026-10-11).
    private var isRecording: Bool {
        monitor.myLiveStream?.isRecordingSession == true
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.white)
                .frame(width: 9, height: 9)
                .opacity(isPulsing ? 0.35 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(isRecording ? "Recording" : "You're live")
                    .font(StreamrFont.headline(14))
                    .foregroundStyle(.white)
                Text(monitor.myLiveStream?.title ?? "")
                    .font(StreamrFont.caption(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                showingConfirmation = true
            } label: {
                ZStack {
                    Text(isRecording ? "Stop Recording" : "End Stream").opacity(monitor.isEnding ? 0 : 1)
                    if monitor.isEnding {
                        ProgressView().tint(.black)
                    }
                }
                .font(StreamrFont.headline(14))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(.white)
                .clipShape(Capsule())
            }
            .disabled(monitor.isEnding)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StreamrColor.liveRed)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .streamrDynamicTypeClamp()
        .onAppear { isPulsing = true }
        .confirmationDialog(isRecording ? "Stop recording?" : "End this stream?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(isRecording ? "Stop Recording" : "End Stream", role: .destructive) {
                Task { await monitor.endLiveStream() }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(isRecording
                 ? "Your recording will be saved and start processing."
                 : "Viewers will be disconnected and the episode will start processing and publishing.")
        }
        .alert(isRecording ? "Couldn't stop the recording" : "Couldn't end the stream", isPresented: Binding(
            get: { monitor.errorMessage != nil },
            set: { if !$0 { monitor.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { monitor.errorMessage = nil }
        } message: {
            Text(monitor.errorMessage ?? "")
        }
    }
}
