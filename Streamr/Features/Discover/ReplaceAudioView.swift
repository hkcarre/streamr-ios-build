import SwiftUI
import UniformTypeIdentifiers

/// The wireframe's "Replace Audio (RSS Only)" — confirmed live 2026-10-02
/// against a disposable test episode, reading orca-nebula's
/// ReplaceAudioModal.tsx + liveStream.ts directly first. Mirrors
/// AddStreamUploadStepView's picker/upload pattern (same presigned-S3 flow,
/// same security-scoped file handling) since this is the same two-step
/// "pick a file, then upload" shape, just a standalone sheet instead of a
/// wizard step.
struct ReplaceAudioView: View {
    let streamId: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var uploader = S3Uploader()
    @State private var showingFileImporter = false
    @State private var pickedFileName: String?
    @State private var pickedFileURL: URL?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("This will only update the audio in the RSS feed. The original video on the platform will not be affected.")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    showingFileImporter = true
                } label: {
                    HStack {
                        Image(systemName: "waveform.badge.plus")
                        Text(pickedFileName ?? "Choose audio file")
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isSubmitting)

                if uploader.isUploading {
                    ProgressView(value: uploader.progress)
                        .tint(StreamrColor.primary)
                    Text("Uploading… \(Int(uploader.progress * 100))%")
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                Spacer()

                PrimaryButton(title: "Replace Audio", isLoading: isSubmitting) {
                    Task { await submit() }
                }
                .disabled(pickedFileURL == nil || isSubmitting)
                .opacity(pickedFileURL == nil ? 0.5 : 1)
            }
            .padding(24)
            .streamrBackground()
            .navigationTitle("Replace Audio (RSS Only)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    handlePickedFile(url)
                }
            }
        }
    }

    /// Same reasoning as AddStreamUploadStepView.handlePickedFile: the
    /// picker's URL is only valid for the security-scoped session, which
    /// can close before the user presses the submit button — copy into a
    /// temp file immediately instead of holding onto the picker's own URL.
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
            errorMessage = "Couldn't read that file. Try picking it again."
        }
    }

    private func submit() async {
        guard let pickedFileURL else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let fileName = pickedFileURL.lastPathComponent
            let fileType = UTType(filenameExtension: pickedFileURL.pathExtension)?.preferredMIMEType ?? "audio/mpeg"

            let uploadInfo = try await APIClient.shared.request(
                API.Streams.generateVideoUploadURL(fileName: fileName, fileType: fileType),
                as: GenerateVideoURLResponse.self
            )

            try await uploader.upload(fileURL: pickedFileURL, to: uploadInfo.uploadURL, contentType: fileType)

            _ = try await APIClient.shared.request(
                API.Streams.replaceAudio(streamId: streamId, fileUrl: uploadInfo.fileUrl.absoluteString),
                as: ReplaceAudioResponse.self
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
