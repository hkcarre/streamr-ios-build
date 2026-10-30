import Foundation

/// Matches the `{ success?, message, data, pagination? }` envelope both
/// orca-nebula and elephant-foundry expect from every endpoint. `success` is
/// optional — confirmed live 2026-08-08 that /stream/public/list and error
/// responses like /category/allCategory's 401 don't actually include it,
/// despite the web apps' TypeScript types claiming it's always present.
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool?
    let message: String?
    let data: T?
    let pagination: Pagination?
}

struct Pagination: Decodable {
    let total: Int
    let page: Int
    let limit: Int
}

/// Used for endpoints whose `data` payload isn't needed by the caller.
struct EmptyData: Decodable {}
