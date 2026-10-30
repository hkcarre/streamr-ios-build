import Foundation

struct Category: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, status
    }
}
