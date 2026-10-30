import Foundation
import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class CreateEditShowViewModel: ObservableObject {
    enum Mode {
        case create
        case edit(Show)
    }

    let mode: Mode

    @Published var name: String
    @Published var description: String
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: String?
    @Published var autoSharing: Bool
    @Published var coverImage: Image?

    /// Edit-mode only — the per-show "Select Platforms" panel. Raw strings
    /// ("youtube", "dailymotion", "twitch", "RSS"), not DestinationProvider,
    /// so the always-available RSS row (not a DestinationProvider case) fits
    /// the same Set without a wrapper enum.
    @Published var selectedProviders: Set<String> = []
    @Published private(set) var connectedAccounts: [ConnectedAccount] = []
    @Published private(set) var isLoadingConnectedAccounts = false
    /// Prefilled from the existing Show in edit mode; nil for .create (a
    /// brand new show has no feed yet). Never sent back to the server —
    /// server-generated, read-only here.
    private(set) var rssLink: String?

    @Published var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            Task { await loadSelectedPhoto() }
        }
    }

    @Published var isLoadingCategories = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var nameError: String?
    @Published private(set) var artworkError: String?
    @Published private(set) var categoryError: String?
    @Published var showingConnectPrompt = false

    private var coverImageData: Data?

    func clearNameError() { nameError = nil }
    func clearCategoryError() { categoryError = nil }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            name = ""
            description = ""
            selectedCategoryId = nil
            autoSharing = false
            rssLink = nil
        case .edit(let show):
            name = show.name
            description = show.description ?? ""
            selectedCategoryId = show.categoryId
            autoSharing = show.autoSharing ?? false
            selectedProviders = Set(show.selectedProviders ?? [])
            rssLink = show.rssLink
        }
    }

    var navigationTitle: String {
        switch mode {
        case .create: return "New Show"
        case .edit: return "Edit Show"
        }
    }

    var saveButtonTitle: String {
        switch mode {
        case .create: return "Create Show"
        case .edit: return "Save Changes"
        }
    }

    @discardableResult
    private func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Give your show a name." : nil

        // Confirmed live 2026-09-01: POST /show/create 400s with "thumbnail is
        // required." if coverPic is omitted — enforce that client-side too,
        // rather than letting the user tap Create and hit a raw server error.
        // /show/update has no such requirement (confirmed: updating without a
        // new photo succeeds, leaves the existing cover untouched), so this
        // only applies to .create. Only sets this if no other artwork error is
        // already showing, so it doesn't clobber a real processing failure.
        if case .create = mode, coverImageData == nil, artworkError == nil {
            artworkError = "Add a cover image — it's required to create a show."
        }

        // Confirmed live 2026-09-02: POST /show/create 400s with "Category is
        // required." if categoryId is omitted — this had no client-side
        // check at all before, so a show created without one silently hit
        // that error, which a since-removed DEBUG fallback then masked by
        // faking local success with a non-Mongo-ID UUID. That fake show then
        // broke stream creation downstream with a confusing "show id must be
        // a valid mongo id" error, several steps removed from the real cause.
        // Not scoped to .create only — unconfirmed whether /show/update also
        // requires it, so require it either way rather than assume it's safe
        // to omit.
        categoryError = selectedCategoryId == nil ? "Choose a category." : nil

        return nameError == nil && artworkError == nil && categoryError == nil
    }

    func loadCategories() async {
        guard categories.isEmpty else { return }
        isLoadingCategories = true
        defer { isLoadingCategories = false }

        do {
            let response = try await APIClient.shared.request(
                API.Discover.categories,
                as: APIResponse<[Category]>.self
            )
            categories = response.data ?? []
        } catch {
            // No mock-data fallback here — unlike a browsable list, a
            // category feeds straight into POST /show/create's required
            // categoryId. A fake MockData category id ("cat1") would look
            // pickable but fail the exact same way the missing-category bug
            // (fixed 2026-09-02, see validate()) did: a confusing rejection
            // several steps downstream. Leaving categories empty here is
            // honest — the picker just has nothing to offer until a retry
            // succeeds, rather than offering options that can't work.
        }
    }

    /// Real backend constraint, confirmed by reading orca-nebula's Yup validator
    /// directly (not the wireframe's paraphrase, which said "reformat to
    /// 2,000 pixels" — the actual rule is a range, not a fixed target): JPG/
    /// JPEG/PNG only, square, 1400-3000px per side, 2MB max. No longer used to
    /// reject a picked photo (see processArtwork below, which now guarantees
    /// these hold by construction instead) — kept as the documented spec and
    /// for its existing unit test coverage.
    // nonisolated: a pure function with no actor-isolated state access — the
    // class being @MainActor would otherwise isolate this too, which is why
    // the first CI run of the accompanying unit test (a plain, non-actor
    // XCTestCase calling it synchronously) failed to compile.
    nonisolated static func validateArtwork(pixelWidth: CGFloat, pixelHeight: CGFloat, jpegByteCount: Int) -> String? {
        guard pixelWidth == pixelHeight else {
            return "Cover art must be a square image."
        }
        guard (1400...3000).contains(pixelWidth) else {
            return "Cover art must be between 1400 and 3000 pixels per side."
        }
        guard jpegByteCount <= 2 * 1024 * 1024 else {
            return "Cover art file is too large — must be 2MB or smaller."
        }
        return nil
    }

    /// Any picked photo works now, whatever its shape or size — rather than
    /// rejecting anything that isn't already square/1400-3000px (the old
    /// behavior, and a real point of user friction: most photos aren't
    /// pre-cropped square), this always center-crops to a square and resizes
    /// to a fixed 2000x2000, matching the wireframe's described "reformat
    /// picture to 2,000 pixels" behavior and landing safely inside
    /// validateArtwork's range. No manual crop UI in v1 — a plain center
    /// crop covers the common case; revisit if users want control over the
    /// crop region.
    nonisolated static func processArtwork(_ image: UIImage) -> (image: UIImage, jpegData: Data)? {
        guard let cgImage = image.cgImage else { return nil }

        let side = min(cgImage.width, cgImage.height)
        let cropRect = CGRect(
            x: CGFloat((cgImage.width - side) / 2),
            y: CGFloat((cgImage.height - side) / 2),
            width: CGFloat(side),
            height: CGFloat(side)
        )
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        let squareImage = UIImage(cgImage: croppedCGImage)

        let targetSide: CGFloat = 2000
        let targetSize = CGSize(width: targetSide, height: targetSide)
        // format.scale = 1 is load-bearing: UIGraphicsImageRenderer defaults
        // to the device's screen scale (often 3x), which would silently
        // render a ~6000x6000px image here instead of 2000x2000 — past the
        // backend's confirmed 3000px max.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            squareImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard var jpegData = resized.jpegData(compressionQuality: 0.9) else { return nil }
        // A 2000x2000 JPEG at 0.9 quality is comfortably under 2MB in
        // practice, but step compression down defensively rather than assume.
        var quality: CGFloat = 0.9
        while jpegData.count > 2 * 1024 * 1024, quality > 0.5 {
            quality -= 0.1
            if let smaller = resized.jpegData(compressionQuality: quality) {
                jpegData = smaller
            }
        }

        return (resized, jpegData)
    }

    private func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        artworkError = nil

        guard let data = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) else {
            artworkError = "Couldn't load that photo. Try a different one."
            return
        }

        guard let processed = Self.processArtwork(uiImage) else {
            artworkError = "Couldn't process that image. Try a different one."
            return
        }

        coverImageData = processed.jpegData
        coverImage = Image(uiImage: processed.image)
    }

    /// Auto-share only works once the user has at least one connected
    /// destination — if none are connected, surface the Destinations screen
    /// right here so they can connect before continuing, rather than saving
    /// a toggle that silently does nothing.
    func autoSharingToggled(_ isOn: Bool) async {
        guard isOn else { return }
        await loadConnectedAccountsIfNeeded(force: true)
        showingConnectPrompt = !connectedAccounts.contains(where: { $0.isConnected })
    }

    /// Feeds the edit-mode "Select Platforms" panel — only connected
    /// providers get a row there, matching the website (AllShowsList.tsx's
    /// `renderPlatform` only renders a provider when its status is
    /// "connected"). `force` re-fetches even if already loaded, used by
    /// autoSharingToggled since connection state can change between the
    /// toggle flip and a prior load (e.g. the user just connected something
    /// via the Manage Connections sheet this same screen presents).
    func loadConnectedAccountsIfNeeded(force: Bool = false) async {
        guard force || connectedAccounts.isEmpty else { return }
        isLoadingConnectedAccounts = true
        defer { isLoadingConnectedAccounts = false }

        do {
            let response = try await APIClient.shared.request(
                API.Destinations.connectedAccounts, as: APIResponse<[ConnectedAccount]>.self
            )
            connectedAccounts = response.data ?? []
        } catch {
            #if DEBUG
            connectedAccounts = MockData.connectedAccounts
            #else
            connectedAccounts = []
            #endif
        }
    }

    func isProviderConnected(_ provider: DestinationProvider) -> Bool {
        connectedAccounts.contains { $0.provider == provider.rawValue && $0.isConnected }
    }

    func toggleProvider(_ raw: String) {
        if selectedProviders.contains(raw) {
            selectedProviders.remove(raw)
        } else {
            selectedProviders.insert(raw)
        }
    }

    func copyRSSLink() -> Bool {
        guard let rssLink, !rssLink.isEmpty else { return false }
        UIPasteboard.general.string = rssLink
        return true
    }

    /// Returns the saved Show, or nil (with errorMessage set) on failure.
    func save() async -> Show? {
        guard validate() else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // `try?` here produced two different lies depending on mode. Creating:
        // a failed upload left coverPicURL nil, the backend rejected the create
        // with "thumbnail is required", and the user was told their artwork was
        // missing seconds after picking it. Editing: the failure was reported
        // as a complete success — `coverPicURL ?? existing.coverPic` fell back
        // to the OLD image, the sheet dismissed, and the user believed the new
        // artwork was saved when it never left the device.
        var coverPicURL: String?
        if let coverImageData {
            do {
                coverPicURL = try await APIClient.shared.uploadImage(
                    data: coverImageData, filename: "cover.jpg", mimeType: "image/jpeg"
                )
            } catch {
                guard !error.isCancellation else { return nil }
                errorMessage = "Couldn't upload the cover image. \(error.localizedDescription)"
                return nil
            }
        }

        let payload = ShowPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            categoryId: selectedCategoryId,
            coverPic: coverPicURL,
            autoSharing: autoSharing,
            selectedProviders: Array(selectedProviders)
        )

        do {
            switch mode {
            case .create:
                let response = try await APIClient.shared.request(
                    API.Shows.create(payload), as: APIResponse<Show>.self
                )
                guard let show = response.data else {
                    throw APIError.server(message: response.message ?? "Show created but no data returned.", statusCode: 0)
                }
                return show
            case .edit(let existing):
                // Confirmed live 2026-10-02: unlike /show/create, /show/update's
                // response is just {message} — no echoed-back Show at all. The
                // old `response.data ?? existing` silently always fell back to
                // the stale pre-edit Show, which would have undone this exact
                // feature (a saved selectedProviders/autoSharing change
                // reverting in the UI right after saving it). Merge the
                // just-sent fields onto `existing` locally instead, same
                // pattern as ShowDetailViewModel.update's sparse-response merge.
                _ = try await APIClient.shared.request(
                    API.Shows.update(id: existing.id, payload), as: APIResponse<EmptyData>.self
                )
                return Show(
                    id: existing.id, name: payload.name, description: payload.description,
                    coverPic: coverPicURL ?? existing.coverPic, categoryId: payload.categoryId,
                    autoSharing: payload.autoSharing, createdAt: existing.createdAt, updatedAt: existing.updatedAt,
                    host: existing.host, streamCount: existing.streamCount, streamScheduledTime: existing.streamScheduledTime,
                    selectedProviders: payload.selectedProviders, rssLink: existing.rssLink
                )
            }
        } catch {
            // No "simulate success" DEBUG fallback here (unlike some reads
            // elsewhere in this app) — this is a write. Confirmed 2026-09-02
            // as the actual cause of a real bug: faking a local Show with a
            // UUID id on failure (e.g. the backend's "Category is required."
            // rejection, previously unvalidated client-side — see validate())
            // let the wizard proceed with a show that only ever existed
            // locally. Stream creation then failed several steps later with
            // a confusing "show id must be a valid mongo id" error, far from
            // the real cause. Always surface the real failure instead.
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
