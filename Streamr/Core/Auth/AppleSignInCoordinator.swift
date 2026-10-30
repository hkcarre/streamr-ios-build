import AuthenticationServices

/// SwiftUI's `SignInWithAppleButton` (used directly in LoginView/SignupView,
/// per Apple's HIG requirement to use their exact button when offering this
/// as a login option) already handles presentation and delegation internally
/// and hands back a `Result<ASAuthorization, Error>` via its onCompletion
/// closure — no custom ASAuthorizationControllerDelegate needed. This just
/// pulls out what the server needs.
///
/// **Confirmed against the live website, 2026-10-20.** The backend does accept
/// `loginType: "Apple"` — the deployed site signs in with it today. Its
/// `useAppleLogin` bundle posts:
///
///     { access_token: <identity token>, loginType: "Apple",
///       name: <display name>, appleAuthCode: <authorization code> }
///
/// The iOS app previously sent only the identity token, which is why Apple
/// sign-in failed here while working on the web. Both the authorization code
/// and the name are now included.
///
/// One difference that cannot be fixed from this side: the website initialises
/// Apple with the **Services ID** `nyc.streamr.web`, while a native app's token
/// is issued to the **bundle id** `nyc.streamr.streamr`. Apple puts that value
/// in the token's `aud` claim, so a server that only accepts the web client id
/// will still reject this one. If it does, the backend needs to accept both
/// audiences — see the note in streamr-backend-tasks.txt.
enum AppleSignInResult {
    struct Credential {
        let identityToken: String
        let authorizationCode: String?
        let email: String?
        let name: String?
    }

    static func parse(_ authorization: ASAuthorization) throws -> Credential {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.server(message: "Apple Sign-In didn't return an identity token.", statusCode: 0)
        }

        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        // Apple hands over the name ONCE, on the very first sign-in for this
        // app, and never again — so it has to be passed on when it appears.
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return Credential(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: credential.email,
            name: name.isEmpty ? nil : name
        )
    }
}
