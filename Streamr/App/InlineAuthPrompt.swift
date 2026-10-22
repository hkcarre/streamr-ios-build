import SwiftUI

/// The guts of `AuthGate.loggedOutPrompt`, extracted so it can be embedded
/// inline (no `NavigationStack`/background of its own) — used directly by
/// `StreamHomeView`'s My Stream segment, where Main Stream must stay visible
/// in the same screen rather than being replaced by a full-screen gate.
struct InlineAuthPrompt: View {
    let prompt: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.5))
            Text(prompt)
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            PrimaryButton(title: "Log In", action: action)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
