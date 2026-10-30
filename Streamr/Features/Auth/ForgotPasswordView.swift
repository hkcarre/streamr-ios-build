import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset password")
                        .font(StreamrFont.title(30))
                    Text("We'll email you a link to reset your password.")
                        .font(StreamrFont.body())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 16)

                if didSubmit {
                    Text("If an account exists for that email, a reset link is on its way.")
                        .font(StreamrFont.body())
                        .foregroundStyle(StreamrColor.primary)
                } else {
                    StreamrTextField(title: "Email", text: $email, keyboardType: .emailAddress, textContentType: .username)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.liveRed)
                    }

                    PrimaryButton(title: "Send reset link", isLoading: isLoading) {
                        Task { await submit() }
                    }
                    .disabled(!email.contains("@"))
                    .opacity(email.contains("@") ? 1 : 0.5)
                }
            }
            .padding(24)
        }
        .streamrBackground()
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.forgotPassword(email: email)
            didSubmit = true
        } catch {
            // Still don't reveal whether the email exists — a server rejection
            // reports success exactly as before.
            //
            // But the previous blanket `didSubmit = true` over-applied that: in
            // airplane mode, or on a bad base URL, the user was told a reset
            // link was on its way and then waited for an email that was never
            // requested. A transport failure says nothing about whether the
            // account exists, so reporting it leaks nothing and is the only way
            // the user learns to retry.
            if error.isCancellation { return }
            if case APIError.transport = error {
                errorMessage = "Couldn't reach Streamr. Check your connection and try again."
                return
            }
            didSubmit = true
        }
    }
}
