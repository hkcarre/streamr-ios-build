import SwiftUI

/// Same shape/sizing as PrimaryButton but outlined/translucent instead of
/// filled — used for the "continue with Google/Facebook" buttons, which
/// shouldn't compete visually with the primary Log In / Sign Up action.
struct SecondaryButton<Icon: View>: View {
    let title: String
    var isLoading: Bool = false
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    icon()
                        .frame(width: 18, height: 18)
                    Text(title)
                        .font(StreamrFont.headline(15))
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isLoading)
    }
}
