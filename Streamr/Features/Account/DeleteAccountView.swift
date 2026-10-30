import SwiftUI

/// DELETE /user/account/delete — already used all session as the
/// disposable-test-account cleanup call, now the real "Delete Account"
/// screen from the wireframe. Matches DeleteAccount.tsx's warning copy.
struct DeleteAccountView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isShowingConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete Account")
                .font(StreamrFont.title(22))
                .foregroundStyle(.white)
            Text("Permanently delete your account and all associated data.")
                .font(StreamrFont.body(15))
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StreamrColor.liveRed)
                    Text("Warning: This action cannot be undone")
                        .font(StreamrFont.headline(15))
                        .foregroundStyle(.white)
                }
                bullet("Your streams will be permanently deleted")
                bullet("Your subscription will be cancelled immediately")
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(StreamrFont.caption())
                    .foregroundStyle(StreamrColor.liveRed)
            }

            Spacer()

            Button {
                isShowingConfirmation = true
            } label: {
                ZStack {
                    Text("Delete My Account").opacity(isDeleting ? 0 : 1)
                    if isDeleting { ProgressView().tint(.white) }
                }
                .font(StreamrFont.headline(17))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(StreamrColor.liveRed)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isDeleting)
        }
        .padding(24)
        .streamrBackground()
        .navigationBarTitleDisplayMode(.inline)
        .alert("Are you sure you want to delete your account?", isPresented: $isShowingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This action is permanent and cannot be undone. You will lose all your data and access to your subscription.")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(StreamrFont.body(14))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            _ = try await APIClient.shared.request(API.User.deleteAccount, as: APIResponse<EmptyData>.self)
            authManager.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
