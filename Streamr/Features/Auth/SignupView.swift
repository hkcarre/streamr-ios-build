import AuthenticationServices
import SwiftUI

struct SignupView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SignupViewModel()
    @State private var isGoogleLoading = false
    @State private var isFacebookLoading = false
    @State private var isAppleLoading = false

    var body: some View {
        ScrollView {
            if let successMessage = viewModel.successMessage {
                signUpSuccessState(message: successMessage)
            } else {
                signUpForm
            }
        }
        .streamrBackground()
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Signup does not log the user in (see AuthManager.signUp) — email
    /// verification is required first, so this replaces the form rather
    /// than auto-dismissing into the (not-yet-authenticated) app.
    private func signUpSuccessState(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 44))
                .foregroundStyle(StreamrColor.primary)
            Text("Check your email")
                .font(StreamrFont.title(24))
            Text(message)
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            PrimaryButton(title: "Back to Log In") {
                dismiss()
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var signUpForm: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 32)
                        .padding(.bottom, 8)
                    Text("Create account")
                        .font(StreamrFont.title(30))
                    Text("Start streaming to every platform at once.")
                        .font(StreamrFont.body())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            StreamrTextField(title: "First name", text: $viewModel.firstName, textContentType: .givenName)
                                .onChange(of: viewModel.firstName) { _, _ in viewModel.clearFirstNameError() }
                            FieldErrorText(message: viewModel.firstNameError)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            StreamrTextField(title: "Last name", text: $viewModel.lastName, textContentType: .familyName)
                                .onChange(of: viewModel.lastName) { _, _ in viewModel.clearLastNameError() }
                            FieldErrorText(message: viewModel.lastNameError)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        StreamrTextField(
                            title: "Email",
                            text: $viewModel.email,
                            keyboardType: .emailAddress,
                            textContentType: .username
                        )
                        .onChange(of: viewModel.email) { _, _ in viewModel.clearEmailError() }
                        FieldErrorText(message: viewModel.emailError)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        StreamrTextField(
                            title: "Password",
                            text: $viewModel.password,
                            isSecure: true,
                            textContentType: .newPassword
                        )
                        .onChange(of: viewModel.password) { _, _ in viewModel.clearPasswordError() }
                        Text("At least 8 characters, with one uppercase letter, one number, and one special character.")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.6))
                        FieldErrorText(message: viewModel.passwordError)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                PrimaryButton(title: "Sign Up", isLoading: viewModel.isLoading) {
                    Task { await viewModel.signUp(using: authManager) }
                }

                OrDivider()

                VStack(spacing: 12) {
                    SecondaryButton(title: "Continue with Google", isLoading: isGoogleLoading) {
                        Image("SocialGoogle").resizable().scaledToFit()
                    } action: {
                        Task { await handleGoogleSignIn() }
                    }

                    SecondaryButton(title: "Continue with Facebook", isLoading: isFacebookLoading) {
                        Image("DestinationFacebook").resizable().scaledToFit()
                    } action: {
                        Task { await handleFacebookSignIn() }
                    }

                    SignInWithAppleButton(.signUp) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(isAppleLoading)
                    .overlay {
                        if isAppleLoading {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                            ProgressView()
                        }
                    }
                }

                // Terms & Conditions is only surfaced via Settings post-signup
                // today (see SettingsView) — a pre-signup agreement checkbox
                // is a reasonable future addition once the flow needs one,
                // not added here to avoid a half-wired consent control.
            }
            .padding(24)
    }

    private func handleGoogleSignIn() async {
        isGoogleLoading = true
        defer { isGoogleLoading = false }
        do {
            let result = try await GoogleAuthService.signIn()
            try await authManager.socialLogin(accessToken: result.accessToken, provider: .google, email: result.email)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleFacebookSignIn() async {
        isFacebookLoading = true
        defer { isFacebookLoading = false }
        do {
            let result = try await FacebookAuthService.signIn()
            try await authManager.socialLogin(accessToken: result.accessToken, provider: .facebook)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isAppleLoading = true
        defer { isAppleLoading = false }
        do {
            let authorization = try result.get()
            let parsed = try AppleSignInResult.parse(authorization)
            try await authManager.socialLogin(
                accessToken: parsed.identityToken,
                provider: .apple,
                email: parsed.email,
                name: parsed.name,
                appleAuthCode: parsed.authorizationCode
            )
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // User dismissed the sheet — not a real error, nothing to show.
        } catch APIError.unauthorized {
            // A 401 here is the SERVER refusing Apple's token, not an expired
            // session — this endpoint sends no token of ours. Without this
            // case the generic text for .unauthorized ("Your session has
            // expired. Please log in again.") appeared on the login screen
            // itself, which is nonsense: there was no session to expire.
            //
            // Confirmed 2026-10-20 against build 22. The likeliest cause is
            // the server checking Apple's token against the WEBSITE's client
            // id (nyc.streamr.web) while a native app's token is issued to
            // the bundle id (nyc.streamr.streamr) — see
            // streamr-backend-tasks.txt item 8.
            viewModel.errorMessage = "Apple couldn't sign you in — the server turned down the request. Email, Google and Facebook still work."
        } catch {
            // Otherwise show what the server actually said.
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
