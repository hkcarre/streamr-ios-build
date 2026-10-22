import XCTest
@testable import Streamr

/// Hits the real production API directly (not through demo mode) and asserts
/// its shape still matches what this app's models expect. This is the
/// automated version of what caught /category/allCategory's actual auth
/// requirement by hand on 2026-08-08 — if the backend drifts from the
/// documented contract in Endpoint.swift, these should fail loudly in CI
/// instead of only being discovered when a real user hits it.
final class ContractTests: XCTestCase {
    private let baseURL = URL(string: "https://api.streamr.nyc/v1")!

    func testPublicStreamListMatchesExpectedContract() async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/stream/public/list"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "type", value: "stream")
        ]

        let (data, response) = try await URLSession.shared.data(from: try XCTUnwrap(components.url))
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "Public stream list should be reachable without auth")

        let decoded = try JSONDecoder().decode(APIResponse<[StreamItem]>.self, from: data)
        // `success` is genuinely absent from this endpoint's real response (confirmed
        // by this test failing until APIResponse.success was made optional) — only
        // assert it isn't explicitly false, not that it's present.
        XCTAssertNotEqual(decoded.success, false)
        XCTAssertNotNil(decoded.pagination, "This app's Discover infinite-scroll relies on pagination being present")
        XCTAssertEqual(decoded.pagination?.limit, 5)
    }

    func testCategoriesStillRequiresAuth() async throws {
        let url = baseURL.appendingPathComponent("/category/allCategory")
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        // Endpoint.swift documents this as requiring auth (confirmed live 2026-08-08,
        // despite looking public from the web frontend's source). If this starts
        // returning 200 without a token, update Endpoint.categories' requiresAuth.
        XCTAssertEqual(http.statusCode, 401, "categories currently requires auth in production")
    }
}
