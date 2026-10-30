import SwiftUI
import UIKit

/// Shows what MetricKit has reported about this device's crashes and hangs.
///
/// Exists so a tester can send a usable crash report without being walked
/// through Console or Xcode — tap the report, tap Send, it arrives as mail at
/// the address Streamr already publishes. Until the backend accepts
/// diagnostics (see `DiagnosticsStore.uploadHandler`), that is the only way
/// one of these leaves the device.
///
/// The empty state does real work here. "No reports" is the normal, healthy
/// answer, and without an explanation of MetricKit's 24-hour batching it reads
/// as "this screen is broken" to someone who just watched the app crash.
struct DiagnosticsView: View {
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if diagnostics.reports.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No reports")
                            .font(StreamrFont.headline(15))
                        Text("iOS collects crashes and hangs in a batch and hands them over at most once a day, on the next launch after they happen. A crash from today usually appears tomorrow.")
                            .font(StreamrFont.body(13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(diagnostics.reports) { report in
                        NavigationLink {
                            DiagnosticReportDetailView(report: report)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(report.kind)
                                        .font(StreamrFont.headline(14))
                                    Spacer()
                                    Text(report.receivedAt, style: .date)
                                        .font(StreamrFont.body(12))
                                        .foregroundStyle(.secondary)
                                }
                                Text(report.summary)
                                    .font(StreamrFont.body(13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                // Worth showing in the list, not just the
                                // detail: a crash in an old build is not the
                                // same news as a crash in the current one.
                                Text("Build \(report.appVersion)")
                                    .font(StreamrFont.body(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Reported by iOS")
                } footer: {
                    Text("Stored on this device only. Open one to send it to \(ReportSheet.contactAddress).")
                }

                Section {
                    Button("Clear reports", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear all reports?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear reports", role: .destructive) { diagnostics.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They can't be recovered once cleared.")
        }
    }
}

/// The full diagnostic, and the two ways to get it off the device.
private struct DiagnosticReportDetailView: View {
    let report: DiagnosticsStore.Report

    @State private var didCopy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.summary)
                        .font(StreamrFont.headline(15))
                    Text("\(report.kind) · build \(report.appVersion)")
                        .font(StreamrFont.body(13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        send()
                    } label: {
                        Text("Send report")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        UIPasteboard.general.string = report.detail
                        didCopy = true
                    } label: {
                        Text(didCopy ? "Copied" : "Copy")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // Monospaced because it is a call-stack tree, and selectable
                // because someone looking at this screen wants to pull one
                // frame out of it rather than read all of it.
                Text(report.detail)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .streamrBackground()
        .navigationTitle(report.kind)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// How much of the detail goes in the mail body.
    ///
    /// A call-stack tree runs to tens of kilobytes and a `mailto:` URL that
    /// long is silently truncated or dropped by the mail client — the failure
    /// looks like "Send did nothing". So the body carries the top of the
    /// report and the clipboard always gets the whole thing, which is also why
    /// `send()` copies even on success.
    private static let mailBodyLimit = 4000

    /// Same `mailto:` hand-off as `ReportSheet`, and the same clipboard
    /// fallback, for the same reason: no extra framework, works with whichever
    /// mail client the person actually uses, and the report is never lost if
    /// none can be opened.
    private func send() {
        UIPasteboard.general.string = report.detail
        didCopy = true

        let excerpt = report.detail.count > Self.mailBodyLimit
            ? String(report.detail.prefix(Self.mailBodyLimit))
                + "\n\n[Truncated for mail. The full report is on the clipboard — paste it below.]"
            : report.detail

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ReportSheet.contactAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Streamr \(report.kind.lowercased()) report (build \(report.appVersion))"),
            URLQueryItem(name: "body", value: "\(report.summary)\n\n\(excerpt)")
        ]

        if let url = components.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
