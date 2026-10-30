import SwiftUI
import PhotosUI

/// Profile picture editing. Two-step flow mirroring the website (orca-nebula
/// `completeProfile.tsx`): upload the bytes to `/user/uploads`, which returns a
/// hosted URL, then persist that URL with `POST /user/complete-profile`.
///
/// The cover photo was dropped from this screen on 2026-10-11 at its author's
/// request ("cover photo unnecessary") — nothing in the iOS app ever displayed
/// it, so it was asking people to pick an image that then went nowhere they
/// could see. The model field, the upload path and
/// `AuthManager.updatePhotos(coverPic:)` are all left intact: the website still
/// shows a cover on the creator page, so the data stays supported even though
/// this screen no longer edits it.
struct EditProfilePhotosView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = EditProfilePhotosViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                photoSection(
                    title: "Profile picture",
                    subtitle: "Shown next to your name and on your episodes.",
                    kind: .profile
                )

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let success = viewModel.successMessage {
                    Text(success)
                        .font(StreamrFont.caption())
                        .foregroundStyle(.green)
                }
            }
            .padding(24)
        }
        .streamrBackground()
        .navigationTitle("Profile Picture")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.attach(authManager) }
    }

    @ViewBuilder
    private func photoSection(title: String, subtitle: String, kind: ProfilePhotoKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(StreamrFont.headline(17))
            Text(subtitle)
                .font(StreamrFont.caption())
                .foregroundStyle(.white.opacity(0.65))

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                if let image = viewModel.pickedImage(for: kind) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = viewModel.currentURL(for: kind, user: authManager.currentUser),
                          let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                } else {
                    Image(systemName: kind == .profile ? "person.crop.circle" : "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.4))
                }

                if viewModel.isBusy(kind) {
                    Color.black.opacity(0.45)
                    ProgressView().tint(.white)
                }
            }
            .frame(height: kind == .profile ? 140 : 110)
            .frame(maxWidth: kind == .profile ? 140 : .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            PhotosPicker(
                selection: viewModel.selectionBinding(for: kind),
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(viewModel.currentURL(for: kind, user: authManager.currentUser) == nil ? "Choose photo" : "Change photo")
                    .font(StreamrFont.headline(15))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(viewModel.isBusy(kind))
        }
    }
}

enum ProfilePhotoKind {
    case profile
    case cover
}

@MainActor
final class EditProfilePhotosViewModel: ObservableObject {
    @Published var profileSelection: PhotosPickerItem? { didSet { handle(profileSelection, kind: .profile) } }
    @Published var coverSelection: PhotosPickerItem? { didSet { handle(coverSelection, kind: .cover) } }

    @Published private(set) var profileImage: UIImage?
    @Published private(set) var coverImage: UIImage?
    @Published private(set) var busyKind: ProfilePhotoKind?
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private weak var authManager: AuthManager?

    func attach(_ manager: AuthManager) {
        authManager = manager
    }

    func pickedImage(for kind: ProfilePhotoKind) -> UIImage? {
        kind == .profile ? profileImage : coverImage
    }

    func currentURL(for kind: ProfilePhotoKind, user: User?) -> String? {
        kind == .profile ? user?.profilePic : user?.coverPic
    }

    func isBusy(_ kind: ProfilePhotoKind) -> Bool {
        busyKind == kind
    }

    func selectionBinding(for kind: ProfilePhotoKind) -> Binding<PhotosPickerItem?> {
        switch kind {
        case .profile:
            return Binding(get: { self.profileSelection }, set: { self.profileSelection = $0 })
        case .cover:
            return Binding(get: { self.coverSelection }, set: { self.coverSelection = $0 })
        }
    }

    private func handle(_ item: PhotosPickerItem?, kind: ProfilePhotoKind) {
        guard let item else { return }
        Task { await upload(item, kind: kind) }
    }

    private func upload(_ item: PhotosPickerItem, kind: ProfilePhotoKind) async {
        busyKind = kind
        errorMessage = nil
        successMessage = nil
        defer { busyKind = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't read that image. Try another one."
                return
            }

            // Re-encode as JPEG rather than forwarding the original bytes: a
            // photo straight from the library can be HEIC and many megabytes,
            // and the backend stores whatever it's handed. 0.85 keeps it
            // visually clean at a fraction of the size.
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else {
                errorMessage = "That image format isn't supported."
                return
            }

            if kind == .profile { profileImage = image } else { coverImage = image }

            let filename = kind == .profile ? "profile.jpg" : "cover.jpg"
            let uploadedURL = try await APIClient.shared.uploadImage(
                data: jpeg, filename: filename, mimeType: "image/jpeg"
            )

            // `/user/complete-profile` replaces the WHOLE profile, so the
            // user's current name and bio have to go back with the photo or
            // they get blanked server-side. See the endpoint's doc comment for
            // why this isn't `/user/updatePageSettings` (that one 400s with
            // "pageName is required" — verified live).
            guard let current = authManager?.currentUser else {
                errorMessage = "Log in again before changing your photos."
                return
            }

            _ = try await APIClient.shared.request(
                API.User.completeProfile(
                    firstName: current.firstName,
                    lastName: current.lastName,
                    bio: current.bio,
                    profilePic: kind == .profile ? uploadedURL : current.profilePic,
                    coverPic: kind == .cover ? uploadedURL : current.coverPic
                ),
                as: APIResponse<EmptyData>.self
            )

            // Keep the cached user in step so the rest of the app shows the new
            // image without a relaunch.
            authManager?.updatePhotos(
                profilePic: kind == .profile ? uploadedURL : nil,
                coverPic: kind == .cover ? uploadedURL : nil
            )
            successMessage = kind == .profile ? "Profile picture updated." : "Cover photo updated."
        } catch {
            errorMessage = error.localizedDescription
            // Drop the optimistic preview so what's shown matches what's saved.
            if kind == .profile { profileImage = nil } else { coverImage = nil }
        }
    }
}
