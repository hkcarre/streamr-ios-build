import Foundation

/// Shared client-side validation, extracted during a correctness audit —
/// previously the password regex lived only inside ChangePasswordView
/// (matching Email&Password.tsx's Yup schema), while SignupViewModel had
/// its own much weaker, unrelated checks (`email.contains("@")`, password
/// length only) that could accept a password the server would reject
/// anyway. The server is always the real source of truth — this exists
/// purely so a bad signup gets caught before round-tripping, same reason
/// ChangePasswordView's check exists.
enum Validators {
    private static let passwordRegex = try! NSRegularExpression(
        pattern: #"^(?=.*[!@#$%^&*()\-_=+{};:,<.>])(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{8,}$"#
    )

    static let passwordRequirementMessage =
        "Password must contain at least 8 characters, one uppercase letter, one number, and one special character."

    static func isValidPassword(_ password: String) -> Bool {
        passwordRegex.firstMatch(in: password, range: NSRange(password.startIndex..., in: password)) != nil
    }

    /// Deliberately simple (RFC 5322 is not worth replicating client-side) —
    /// just enough to catch an obviously malformed address before hitting
    /// the server, which does the real validation.
    private static let emailRegex = try! NSRegularExpression(
        pattern: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
    )

    static func isValidEmail(_ email: String) -> Bool {
        emailRegex.firstMatch(in: email, range: NSRange(email.startIndex..., in: email)) != nil
    }
}
