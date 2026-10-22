import Foundation

/// Notification posted on any 401 response, mirroring the web apps' axios
/// response interceptor that force-logs-out on an expired/invalid token.
extension Notification.Name {
    static let streamrDidReceiveUnauthorized = Notification.Name("streamrDidReceiveUnauthorized")
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(session: URLSession = .shared) {
        self.session = session

        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    @discardableResult
    func request<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        var components = URLComponents(
            url: try AppConfig.apiBaseURL().appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty {
            components?.queryItems = endpoint.query
        }

        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // An authenticated endpoint with no token NEVER goes to the network.
        //
        // This used to send the request anyway, just without an Authorization
        // header, which the backend answered with 401 — and a 401 force-logs
        // the session out (see `decode`). That is how a signed-in user ended up
        // being told they weren't signed in (reported 2026-10-11):
        //
        //   1. App opens as a guest. DiscoverView's `loadInitial` calls
        //      `/category/allCategory`, which requires auth. No token, so the
        //      request goes out bare and is doomed to 401.
        //   2. The user signs in. Token saved, `isAuthenticated` true.
        //   3. The request from step 1 finally returns 401.
        //   4. The 401 handler tears the session down — logging out the user
        //      who had just successfully logged in.
        //
        // Failing locally closes that race: there is no in-flight doomed
        // request left to land after a successful login.
        var didSendToken = false
        if endpoint.requiresAuth {
            guard let token = KeychainStore.loadToken() else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            didSendToken = true
        }

        if let body = endpoint.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await perform(request)
        return try decode(T.self, from: data, response: response, didSendToken: didSendToken)
    }

    /// Uploads image data as multipart/form-data to POST /user/uploads and returns
    /// the resulting URL. Confirmed live 2026-09-01: `data` is an array of URL
    /// strings (one per uploaded file), not a `{url: ...}` object as first guessed.
    func uploadImage(data imageData: Data, filename: String, mimeType: String) async throws -> String {
        let url = try AppConfig.apiBaseURL().appendingPathComponent(API.Media.uploadPath)

        var request = URLRequest(url: url)
        request.httpMethod = Endpoint.Method.post.rawValue

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Uploads are always authenticated — same reasoning as `request`: don't
        // send a request that can only 401 and take the session down with it.
        guard let token = KeychainStore.loadToken() else {
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await perform(request)
        let decoded = try decode(
            APIResponse<[String]>.self, from: responseData, response: response, didSendToken: true
        )
        guard let uploadedURL = decoded.data?.first else {
            throw APIError.server(message: decoded.message ?? "Upload succeeded but returned no URL.", statusCode: 0)
        }
        return uploadedURL
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        return (data, http)
    }

    /// `didSendToken` decides whether a 401 means "your session is over" or
    /// merely "that endpoint needs auth". Only a token we actually sent and the
    /// server rejected proves the session is dead; a 401 on a request that
    /// carried no credentials proves nothing about the session and must not end
    /// it.
    ///
    /// The token is no longer deleted here. AuthManager owns session teardown
    /// and does it in one place (token AND cached profile); clearing half of it
    /// from the networking layer left the two stores able to disagree.
    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        response http: HTTPURLResponse,
        didSendToken: Bool
    ) throws -> T {
        if http.statusCode == 401 {
            if didSendToken {
                NotificationCenter.default.post(name: .streamrDidReceiveUnauthorized, object: nil)
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIResponse<EmptyData>.self, from: data))?.message
                ?? "Request failed with status \(http.statusCode)."
            throw APIError.server(message: message, statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // A 2xx status doesn't guarantee `data` matches the shape the caller
            // expected — confirmed live 2026-09-01: logging in before verifying
            // email returns HTTP 200 with a *different* data shape
            // ({sendReVerifyMail: true} instead of a User) and a genuinely
            // useful `message` ("Please verify your email."). Surface that
            // message instead of a generic decode error whenever the response
            // has one, rather than silently discarding it.
            if let message = (try? decoder.decode(APIResponse<EmptyData>.self, from: data))?.message {
                throw APIError.server(message: message, statusCode: http.statusCode)
            }
            throw APIError.decoding(error)
        }
    }
}

/// Type-erasing wrapper so `Endpoint.body: Encodable?` can be encoded directly.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
