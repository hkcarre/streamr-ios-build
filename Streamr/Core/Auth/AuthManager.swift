import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated: Bool = false

    /// Set when the SERVER rejected a token we held, as opposed to the user
    /// choosing to log out.
    ///
    /// Without this the two are indistinguishable on screen: the app simply
    /// reverts to its guest state, which reads as "it forgot I was logged in"
    /// rather than "your session ended". Cleared once shown.
    @Published var sessionExpired = false

    private var cancellable: AnyCancellable?

    init() {
        isAuthenticated = KeychainStore.loadToken() != nil
        // Restore WHO we're signed in as, not just THAT we're signed in.
        // Previously only the token came back on launch, leaving currentUser
        // nil — see KeychainStore.saveUser for what that broke.
        if isAuthenticated {
            currentUser = KeychainStore.loadUser()
        }

        cancellable = NotificationCenter.default
            .publisher(for: .streamrDidReceiveUnauthorized)
            .sink { [weak self] _ in
                guard let self, self.isAuthenticated else { return }
                self.logout()
                self.sessionExpired = true
            }
    }

    func login(email: String, password: String) async throws {
        let response = try await APIClient.shared.request(
            API.Auth.login(email: email, password: password),
            as: APIResponse<User>.self
        )
        try apply(response)
    }

    /// Unlike login, signup does NOT authenticate the user immediately — confirmed
    /// live 2026-09-01 against a real test account. `data` is just the new user's
    /// bare ID string (not a User object, no token at all); the backend requires
    /// email verification (a link to streamr.nyc/verify-email/:token, which calls
    /// GET /onboarding/verify/email/:token) before login will succeed. Returns the
    /// server's message (e.g. "check your email") for the UI to show — callers
    /// must NOT treat a successful signup as being logged in.
    @discardableResult
    func signUp(firstName: String, lastName: String, email: String, password: String) async throws -> String {
        let response = try await APIClient.shared.request(
            API.Auth.signUp(firstName: firstName, lastName: lastName, email: email, password: password),
            as: APIResponse<String>.self
        )
        return response.message ?? "Check your email to verify your account, then log in."
    }

    /// All three providers follow the same contract the website uses.
    ///
    /// `name` and `appleAuthCode` are Apple's extras: the deployed site posts
    /// both on every Apple sign-in, and omitting the authorization code is why
    /// this failed from iOS while working on the web (read out of the live
    /// bundle, 2026-10-20). Google and Facebook simply leave them nil.
    func socialLogin(
        accessToken: String,
        provider: SocialLoginProvider,
        email: String? = nil,
        name: String? = nil,
        appleAuthCode: String? = nil
    ) async throws {
        let response = try await APIClient.shared.request(
            API.Auth.socialLogin(
                accessToken: accessToken, loginType: provider, email: email,
                name: name, appleAuthCode: appleAuthCode
            ),
            as: APIResponse<User>.self
        )
        try apply(response)
    }

    func forgotPassword(email: String) async throws {
        _ = try await APIClient.shared.request(
            API.Auth.forgotPassword(email: email),
            as: APIResponse<EmptyData>.self
        )
    }

    func logout() {
        KeychainStore.deleteToken()
        KeychainStore.deleteUser()
        currentUser = nil
        isAuthenticated = false
    }

    /// Patches the cached user after a successful photo upload so the new
    /// image shows everywhere immediately, without a relaunch or a refetch.
    /// Each argument is optional and nil means "leave this one alone", matching
    /// `PageSettingsPayload`'s own omit-rather-than-null behaviour.
    func updatePhotos(profilePic: String? = nil, coverPic: String? = nil) {
        guard var user = currentUser else { return }
        if let profilePic { user.profilePic = profilePic }
        if let coverPic { user.coverPic = coverPic }
        currentUser = user
        // Persist too, so the new photo survives a relaunch rather than
        // reverting to whatever was cached at login.
        KeychainStore.saveUser(user)
    }

    #if DEBUG
    /// Lets the app be browsed end-to-end before a real backend URL exists —
    /// used by the "Continue with Demo Data" button and CI screenshot tests.
    func loginAsDemoUser() {
        KeychainStore.saveToken(MockData.user.token ?? "demo-token")
        KeychainStore.saveUser(MockData.user)
        currentUser = MockData.user
        isAuthenticated = true
    }
    #endif

    private func apply(_ response: APIResponse<User>) throws {
        guard let user = response.data, let token = user.token else {
            throw APIError.server(message: response.message ?? "Login failed.", statusCode: 0)
        }
        KeychainStore.saveToken(token)
        KeychainStore.saveUser(user)
        currentUser = user
        isAuthenticated = true
    }
}
