import SwiftUI
import UIKit

/// Wraps UIActivityViewController so the OS share sheet can be presented
/// directly — matches the wireframe's "Invite Guest Popup tray" (shown
/// already open, layered over the app). SwiftUI's own ShareLink only offers
/// a tap-to-open button, it can't auto-present like this.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Its own step between episode details and the staging/camera screen — the
/// wireframe's "Invite Guest Popup tray" appears here, before camera/mic
/// permission is ever requested, since sharing a link shouldn't be gated on
/// that. Only reached when the guest toggle was checked (see
/// AddStreamCoordinator.beginLiveStage).
struct AddStreamInviteGuestStepView: View {
    @ObservedObject var coordinator: AddStreamCoordinator
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(StreamrColor.primary)

            Text("Invite a guest")
                .font(StreamrFont.headline(20))
                .foregroundStyle(.white)

            Text(
                coordinator.guestInviteURL != nil
                    ? "Share this link so someone can join you live — first to open it gets the second spot."
                    : "Couldn't generate an invite link — you can still go live without a guest."
            )
            .font(StreamrFont.body())
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            PrimaryButton(title: "Continue") {
                coordinator.proceedToStaging()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .onAppear {
            if coordinator.guestInviteURL != nil {
                showingShareSheet = true
            }
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: {
            coordinator.proceedToStaging()
        }) {
            if let url = coordinator.guestInviteURL {
                ActivityShareSheet(items: [url])
            }
        }
    }
}
