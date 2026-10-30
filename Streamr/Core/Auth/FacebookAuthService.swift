import FBSDKCoreKit
import FBSDKLoginKit

/// Thin wrapper around FBSDKLoginKit so LoginView/SignupView don't touch the
/// SDK directly. Needs real FACEBOOK_APP_ID/FACEBOOK_CLIENT_TOKEN (piped from
/// Config/*.xcconfig — currently REPLACE_ME placeholders) before this does
/// anything but fail with a Facebook-side configuration error.
enum FacebookAuthService {
    struct SignInResult {
        let accessToken: String
    }

    @MainActor
    static func signIn() async throws -> SignInResult {
        guard let presenting = PresentationContext.topMostViewController() else {
            throw APIError.server(message: "Couldn't find a screen to present Facebook Login from.", statusCode: 0)
        }

        return try await withCheckedThrowingContinuation { continuation in
            LoginManager().logIn(permissions: ["public_profile", "email"], from: presenting) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if result?.isCancelled == true {
                    continuation.resume(throwing: APIError.server(message: "Facebook login was cancelled.", statusCode: 0))
                    return
                }
                // Confirmed to match what the web app sends
                // (response.accessToken) — see Endpoint.swift's socialLogin doc.
                guard let tokenString = AccessToken.current?.tokenString else {
                    continuation.resume(throwing: APIError.server(message: "Facebook didn't return an access token.", statusCode: 0))
                    return
                }
                continuation.resume(returning: SignInResult(accessToken: tokenString))
            }
        }
    }
}
