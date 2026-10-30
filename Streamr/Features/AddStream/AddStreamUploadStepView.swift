import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The one fully real, end-to-end wizard path. `.fileImporter` rather than
/// `PhotosPicker` — audio files generally aren't in the Photos library, so
/// this is the structurally correct choice for both Video and Audio through
/// one symmetric code path. Matches the wireframe's two-step flow: pick a
/// file first, then press Share to actually start the upload.
struct AddStreamUploadStepView: View {
    @ObservedObject var coordinator: AddStreamCoordinator
    @State private var showingFileImporter = false
    @State private var pickedFileName: String?
    @State private var pickedFileURL: URL?

    /// `isSubmittingUpload`, not `uploader.isUploading` — the latter is false
    /// during the presigned-URL round trip that precedes the actual transfer,
    /// which left the Share button tappable a second time. See
    /// AddStreamCoordinator.isSubmittingUpload.
    private var isBusy: Bool {
        coordinator.isSubmittingUpload || coordinator.uploader.isUploading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    showingFileImporter = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text(pickedFileName ?? "Choose File")
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isBusy)

                if coordinator.uploader.isUploading {
                    ProgressView(value: coordinator.uploader.progress)
                        .tint(StreamrColor.primary)
                    Text("Uploading… \(Int(coordinator.uploader.progress * 100))%")
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let wizardError = coordinator.wizardError {
                    Text(wizardError)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                PrimaryButton(title: "Share", isLoading: isBusy) {
                    guard let pickedFileURL else { return }
                    Task { await coordinator.beginUpload(localFileURL: pickedFileURL) }
                }
                .disabled(pickedFileURL == nil || isBusy)
                .opacity(pickedFileURL == nil ? 0.5 : 1)
            }
            .padding(24)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: coordinator.format == .video ? [.movie] : [.audio]
        ) { result in
            if case .success(let url) = result {
                handlePickedFile(url)
            }
        }
    }

    /// `.fileImporter`'s URL is only valid for the duration of the security-
    /// scoped access session, which closes fast (especially for iCloud-backed
    /// files) — copy into a temp file immediately, before that window closes,
    /// rather than trying to upload directly from the picker's URL later
    /// (when the user presses Share).
    private func handlePickedFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.copyItem(at: url, to: destination)
            pickedFileName = url.lastPathComponent
            pickedFileURL = destination
        } catch {
            coordinator.wizardError = "Couldn't read that file. Try picking it again."
        }
    }
}
