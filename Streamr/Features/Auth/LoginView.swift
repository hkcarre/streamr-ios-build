import AuthenticationServices
import SwiftUI

/// Always presented as a sheet now (from AuthGate or Discover's guest "Log In"
/// button) — never the app's root view, since Discover is open to guests.
struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LoginViewModel()
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @State private var isGoogleLoading = false
    @State private var isFacebookLoading = false
    @State private var isAppleLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 40)
                        Text("Log in to go live.")
                            .font(StreamrFont.body())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 14) {
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
                                textContentType: .password
                            )
                            .onChange(of: viewModel.password) { _, _ in viewModel.clearPasswordError() }
                            FieldErrorText(message: viewModel.passwordError)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.liveRed)
                    }

                    Button("Forgot password?") {
                        showForgotPassword = true
                    }
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.8))

                    PrimaryButton(title: "Log In", isLoading: viewModel.isLoading) {
                        Task { await viewModel.login(using: authManager) }
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

                        SignInWithAppleButton(.continue) { request in
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

                    HStack {
                        Text("Don't have an account?")
                            .foregroundStyle(.white.opacity(0.75))
                        Button("Sign up") {
                            showSignUp = true
                        }
                        .foregroundStyle(StreamrColor.primary)
                    }
                    .font(StreamrFont.body(14))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    #if DEBUG
                    Button {
                        authManager.loginAsDemoUser()
                    } label: {
                        Text("Continue with Demo Data")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                    #endif
                }
                .padding(24)
            }
            .streamrBackground()
            .navigationDestination(isPresented: $showSignUp) { SignupView() }
            .navigationDestination(isPresented: $showForgotPassword) { ForgotPasswordView() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated { dismiss() }
            }
        }
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
