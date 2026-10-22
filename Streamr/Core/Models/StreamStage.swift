import Foundation

/// Confirmed by reading orca-nebula's real stream-creation wizard source
/// (Steps/step2.tsx, step3.tsx) — "Record" is not a local-record-then-upload
/// flow, it goes through the identical AWS IVS publish pipeline as "Stream,"
/// just additionally triggers server-side recording. "Upload" is the only
/// type with zero AWS IVS involvement (a plain S3 file upload).
enum VideoType: String, Codable, CaseIterable, Identifiable, Hashable {
    case stream
    case record
    case upload

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stream: "Stream"
        case .record: "Record"
        case .upload: "Upload"
        }
    }
}

enum StreamFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case video = "Video"
    case audio = "Audio"

    var id: String { rawValue }
}

/// Confirmed binary — the wireframe's "Chat On/Off" maps to this, not a true
/// three-state toggle (there's no way to omit chat entirely once type is
/// .stream; "Off" in the UI just sends .privateChat).
enum ChatVisibility: String, Codable, Hashable {
    case publicChat = "Public"
    case privateChat = "Private"
}
