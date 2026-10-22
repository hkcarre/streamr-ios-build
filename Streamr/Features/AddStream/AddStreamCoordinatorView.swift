import SwiftUI

/// Sheet root for the Add Stream wizard, presented from the center tab.
/// A flat switch over `coordinator.step` rather than NavigationPath-driven
/// push navigation — the coordinator already fully owns step transitions,
/// so NavigationPath's Hashable/type-erasure boilerplate wouldn't earn its
/// keep here.
struct AddStreamCoordinatorView: View {
    @StateObject private var coordinator = AddStreamCoordinator()
    @Environment(\.dismiss) private var dismiss
    @State private var showingLeaveWhileLiveAlert = false
    @State private var isEndingFromCancel = false

    private var isBroadcasting: Bool {
        coordinator.stageManager.isPublishing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.step {
                case .loadingShows:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .chooseOrCreateShow:
                    AddStreamShowStepView(coordinator: coordinator)
                case .typeAndFormat:
                    AddStreamTypeFormatStepView(coordinator: coordinator)
                case .episodeDetails:
                    AddStreamEpisodeDetailsStepView(coordinator: coordinator)
                case .uploadProgress:
                    AddStreamUploadStepView(coordinator: coordinator)
                case .inviteGuest:
                    AddStreamInviteGuestStepView(coordinator: coordinator)
                case .staging:
                    AddStreamStagingView(coordinator: coordinator)
                case .done:
                    AddStreamDoneView { dismiss() }
                }
            }
            .streamrBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavBarLogo()
                }
                ToolbarItem(placement: .cancellationAction) {
                    // Never disabled. It used to be disabled for the whole end
                    // attempt, and that attempt is a 2.5s drain plus a network
                    // call on URLSession's 60s default timeout — so a hung
                    // request removed the only remaining exit for a full
                    // minute. "Discard & Close" in the alert is purely local
                    // and works instantly, so leaving this live always gives a
                    // way out, even mid-attempt.
                    // Always "Cancel". It used to become "Stop" mid-attempt,
                    // which put a second, differently-named stop control in the
                    // toolbar while the real one sat at the bottom of the
                    // screen — "when I hit cancel then the stop button shows
                    // up" (2026-10-14). Stopping belongs to the button at the
                    // bottom; this one only ever leaves.
                    Button("Cancel") {
                        if isBroadcasting || isEndingFromCancel {
                            showingLeaveWhileLiveAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            // A sheet can be swiped away, which would walk out on a live
            // broadcast without the Cancel button ever being touched. Blocked
            // while publishing so the alert below is the only way out.
            .interactiveDismissDisabled(isBroadcasting)
            // Always offers a real way out.
            //
            // This previously had only "End & Save" and "Keep Broadcasting",
            // and End & Save dismissed ONLY on success. Combined with
            // interactive dismissal being blocked while live, a `/stream/end`
            // that kept failing left no exit at all short of force-quitting —
            // reported 2026-10-11 as "a screen saying I'm streaming but I'm
            // not and I can't stop either". Discard & Close is the guaranteed
            // escape: it goes off air immediately and says plainly what that
            // costs.
            .alert("You're still broadcasting", isPresented: $showingLeaveWhileLiveAlert) {
                Button("End & Save") {
                    Task {
                        isEndingFromCancel = true
                        let ended = await coordinator.finishLiveSession()
                        isEndingFromCancel = false
                        // On failure stay put so the staging screen's own
                        // retry/force-stop alert can take over, rather than
                        // dismissing and implying the episode was saved.
                        if ended { dismiss() }
                    }
                }
                Button("Discard & Close", role: .destructive) {
                    coordinator.stopBroadcastingLocally()
                    dismiss()
                }
                Button("Keep Broadcasting", role: .cancel) {}
            } message: {
                Text("End & Save stops the stream and lets the episode process and publish. Discard & Close takes you off air straight away, but the episode may not publish.")
            }
            .task { await coordinator.start() }
        }
    }
}
