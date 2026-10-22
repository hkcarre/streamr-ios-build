import GoogleSignIn

/// Thin wrapper around GIDSignIn so LoginView/SignupView don't touch the SDK
/// directly. Needs a real GOOGLE_CLIENT_ID (Info.plist's GIDClientID key,
/// piped from Config/*.xcconfig — currently a REPLACE_ME placeholder) before
/// this does anything but fail with a Google-side configuration error.
enum GoogleAuthService {
    struct SignInResult {
        let accessToken: String
        let email: String?
    }

    @MainActor
    static func signIn() async throws -> SignInResult {
        guard let presenting = PresentationContext.topMostViewController() else {
            throw APIError.server(message: "Couldn't find a screen to present Google Sign-In from.", statusCode: 0)
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        // Confirmed to match what the web app sends (useGoogleLogin's
        // tokenResponse.access_token) — see Endpoint.swift's socialLogin doc.
        return SignInResult(accessToken: result.user.accessToken.tokenString, email: result.user.profile?.email)
    }
}
