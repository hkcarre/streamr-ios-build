import Foundation

/// Raw PUT to an arbitrary presigned S3 URL — deliberately separate from
/// APIClient, since this doesn't touch AppConfig.apiBaseURL(), an auth
/// header, or the APIResponse<T> JSON envelope at all (S3 presigned URLs
/// carry their own auth in the query string).
@MainActor
final class S3Uploader: NSObject, ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isUploading = false

    /// Uses the file-based upload(for:fromFile:delegate:) overload rather
    /// than the Data-based one, so a large video isn't fully buffered in
    /// memory. Passing `self` as the per-call delegate is what lets an
    /// async/await upload still receive URLSessionTaskDelegate progress
    /// callbacks (iOS 15+) — no separately-configured URLSession needed.
    func upload(fileURL: URL, to uploadURL: URL, contentType: String) async throws {
        isUploading = true
        progress = 0
        defer { isUploading = false }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL, delegate: self)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.server(message: "Upload failed with status \(statusCode).", statusCode: statusCode)
        }
    }
}

extension S3Uploader: URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let value = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            self.progress = value
        }
    }
}
