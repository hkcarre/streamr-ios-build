import SwiftUI

/// PUT /user/changepassword, confirmed live 2026-09-28. Client-side
/// validation mirrors Email&Password.tsx's Yup schema exactly (8+ chars,
/// one upper, one lower, one digit, one special char; new != old;
/// confirm == new) so a bad password gets caught before round-tripping to
/// the server, matching the website's own UX.
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    /// No NavigationStack of its own. AccountView pushes this with a
    /// NavigationLink, so wrapping it in a second stack drew two nav bars
    /// stacked on each other — the pushed bar with Back, and an inner bar with
    /// the title and a Cancel button that did the same thing as Back. Every
    /// other screen pushed from AccountView (Destinations, Plans, Payment
    /// Methods, Photos, Delete Account) correctly omits it; this was the odd
    /// one out. `dismiss()` still pops correctly from a pushed view.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StreamrTextField(title: "Old Password", text: $oldPassword, isSecure: true)
                StreamrTextField(title: "New Password", text: $newPassword, isSecure: true)
                StreamrTextField(title: "Confirm New Password", text: $confirmNewPassword, isSecure: true)

                Text("At least 8 characters, with one uppercase letter, one number, and one special character.")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))

                if let errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                PrimaryButton(title: "Update Password", isLoading: isSaving) {
                    Task { await submit() }
                }
            }
            .padding(24)
        }
        .streamrBackground()
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("OK") { dismiss() }
        } message: {
            Text(successMessage ?? "")
        }
    }

    private func validate() -> String? {
        guard !oldPassword.isEmpty else { return "Old password is required." }
        guard Validators.isValidPassword(newPassword) else {
            return "New " + Validators.passwordRequirementMessage
        }
        guard newPassword != oldPassword else { return "New password should be different than old password." }
        guard newPassword == confirmNewPassword else { return "New password and confirm new password should be the same." }
        return nil
    }

    private func submit() async {
        if let validationError = validate() {
            errorMessage = validationError
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let response = try await APIClient.shared.request(
                API.User.changePassword(
                    oldPassword: oldPassword, newPassword: newPassword, confirmNewPassword: confirmNewPassword
                ),
                as: APIResponse<EmptyData>.self
            )
            // HTTP 200 doesn't guarantee success here — confirmed live: a
            // wrong old password still returns 200 with success: false.
            if response.success == false {
                errorMessage = response.message ?? "Failed to update password."
                return
            }
            successMessage = response.message ?? "Password updated successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
