import Foundation

@MainActor
final class SignupViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// Set on a successful signup — the user is NOT logged in at this point
    /// (see AuthManager.signUp), so the view shows this instead of dismissing.
    @Published private(set) var successMessage: String?

    @Published private(set) var firstNameError: String?
    @Published private(set) var lastNameError: String?
    @Published private(set) var emailError: String?
    @Published private(set) var passwordError: String?

    func clearFirstNameError() { firstNameError = nil }
    func clearLastNameError() { lastNameError = nil }
    func clearEmailError() { emailError = nil }
    func clearPasswordError() { passwordError = nil }

    @discardableResult
    private func validate() -> Bool {
        firstNameError = firstName.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter your first name." : nil
        lastNameError = lastName.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter your last name." : nil
        emailError = Validators.isValidEmail(email) ? nil : "Enter a valid email address."
        passwordError = Validators.isValidPassword(password) ? nil : Validators.passwordRequirementMessage
        return firstNameError == nil && lastNameError == nil && emailError == nil && passwordError == nil
    }

    func signUp(using authManager: AuthManager) async {
        guard validate() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            successMessage = try await authManager.signUp(
                firstName: firstName, lastName: lastName, email: email, password: password
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
