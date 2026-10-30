import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var emailError: String?
    @Published private(set) var passwordError: String?

    func clearEmailError() { emailError = nil }
    func clearPasswordError() { passwordError = nil }

    /// Validates and surfaces specific field errors immediately, rather than
    /// silently disabling the submit button with no explanation.
    @discardableResult
    private func validate() -> Bool {
        emailError = email.contains("@") ? nil : "Enter a valid email address."
        passwordError = password.isEmpty ? "Enter your password." : nil
        return emailError == nil && passwordError == nil
    }

    func login(using authManager: AuthManager) async {
        guard validate() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
