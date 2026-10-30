import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(message: String, statusCode: Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .server(let message, _):
            return message
        case .decoding:
            return "Received an unexpected response from the server."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

extension Error {
    /// True when this error is "the work was called off", not "the work
    /// failed" — a cancelled `Task`, or a URLSession request torn down with
    /// `NSURLErrorCancelled` (-999) because the Task owning it was cancelled.
    ///
    /// Exists because SwiftUI's `.refreshable` cancels its Task as soon as the
    /// pull-to-refresh gesture finishes, which is routine and expected. Showing
    /// `error.localizedDescription` for it put the literal word **"cancelled"**
    /// on screen as if something had gone wrong — reported 2026-10-11 as
    /// "slide down/refresh on Main Stream gives 'cancelled' error". Nothing had
    /// gone wrong; the only bug was treating a cancellation as a failure.
    ///
    /// Checks the whole `underlyingError` chain, because `APIError.transport`
    /// wraps the URLError rather than replacing it.
    var isCancellation: Bool {
        if self is CancellationError { return true }

        var next: Error? = self
        while let current = next {
            let nsError = current as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return true
            }
            if case APIError.transport(let wrapped) = current {
                next = wrapped
                continue
            }
            next = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }
}
