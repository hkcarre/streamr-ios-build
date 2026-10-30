import SwiftUI
import UIKit

/// What is being reported, and who it belongs to.
///
/// One type for both surfaces so `ReportSheet` doesn't branch on content kind
/// and so the message body always carries the same fields.
struct ReportSubject: Equatable, Identifiable {
    enum Kind: String {
        case episode = "Episode"
        case chatMessage = "Chat message"
    }

    let kind: Kind
    /// Episode id, or chat message id — whatever identifies the thing
    /// server-side, so a human reading the report can find it.
    let contentId: String
    /// Episode title, or the message text.
    let contentDescription: String
    /// The person who published it, if known.
    let authorId: String?
    let authorName: String

    /// Identity for `.sheet(item:)`. Keyed on the content, not the author:
    /// reporting two different messages from the same person must present two
    /// distinct sheets.
    var id: String { "\(kind.rawValue):\(contentId)" }

    var blockKey: ModerationStore.Key {
        if let authorId, !authorId.isEmpty { return .userId(authorId) }
        return .displayName(authorName)
    }
}

/// The reasons offered. Deliberately short — a long list makes people pick
/// "Other" and write nothing useful.
enum ReportReason: String, CaseIterable, Identifiable {
    case sexualContent = "Nudity or sexual content"
    case violence = "Violence or threats"
    case harassment = "Harassment or hate speech"
    case illegal = "Illegal activity"
    case spam = "Spam or misleading"
    case other = "Something else"

    var id: String { rawValue }
}

/// Report flow for user-generated content.
///
/// App Store Review Guideline 1.2 requires "a mechanism to report offensive
/// content and timely responses to concerns". This is that mechanism.
///
/// **Why it sends mail rather than calling the API.** There is no report
/// endpoint. Checked against the live API 2026-10-22 — nothing under
/// `/report`, `/user/block` or any sibling, and the full endpoint surface is
/// in Endpoint.swift. So the report is composed into a mail to the address
/// Streamr itself publishes on its Help & Support page
/// (`source@streamr.nyc`, read from `GET /v1/cms/detail/help-support` the same
/// day), which satisfies the guideline and reaches a real human.
///
/// `mailto:` via `openURL` rather than `MFMailComposeViewController`: it needs
/// no extra framework and no UIKit view-controller bridge, and it works with
/// whichever mail client the person actually uses. If no mail client can
/// handle it the text is copied to the clipboard and the address shown, so the
/// report is never simply lost.
///
/// Replace the body of `submit()` with an API call the moment the backend has
/// one — item added to streamr-backend-tasks.txt.
struct ReportSheet: View {
    /// Where reports go. Published by Streamr on its own Help & Support page;
    /// not invented here.
    static let contactAddress = "source@streamr.nyc"

    let subject: ReportSubject

    @EnvironmentObject private var moderation: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .harassment
    @State private var note: String = ""
    @State private var alsoBlock = true
    @State private var didFallBackToClipboard = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What's wrong with this \(subject.kind.rawValue.lowercased())?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Anything else we should know?") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Also block \(subject.authorName)", isOn: $alsoBlock)
                } footer: {
                    Text("Blocking hides their episodes and chat messages from you on this device. You can undo it in Blocked accounts.")
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        Text("Send report")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    if didFallBackToClipboard {
                        Text("No mail app could be opened, so the report was copied to your clipboard. Please send it to \(Self.contactAddress).")
                            .foregroundStyle(StreamrColor.warningGold)
                    } else {
                        Text("Reports go to \(Self.contactAddress).")
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        // Block first. If the mail hand-off fails or the person abandons their
        // mail app, the thing they actually wanted — to stop seeing this
        // person — has still happened.
        if alsoBlock {
            moderation.block(subject.blockKey, displayName: subject.authorName)
        }

        let body = reportBody()
        if let url = mailtoURL(body: body), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            didSubmit = true
            dismiss()
        } else {
            UIPasteboard.general.string = "To: \(Self.contactAddress)\n\n\(body)"
            didFallBackToClipboard = true
        }
    }

    private func reportBody() -> String {
        var lines: [String] = [
            "Reported from the Streamr iOS app.",
            "",
            "Type:    \(subject.kind.rawValue)",
            "Reason:  \(reason.rawValue)",
            "Content: \(subject.contentId)",
            "Author:  \(subject.authorName)\(subject.authorId.map { " (\($0))" } ?? "")",
            ""
        ]
        if !subject.contentDescription.isEmpty {
            lines.append("What was reported:")
            lines.append(subject.contentDescription)
            lines.append("")
        }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Additional detail from the reporter:")
            lines.append(note)
        }
        return lines.joined(separator: "\n")
    }

    private func mailtoURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.contactAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Streamr report: \(reason.rawValue)"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
