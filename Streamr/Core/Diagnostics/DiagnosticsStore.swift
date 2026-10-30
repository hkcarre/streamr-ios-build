import Foundation
import MetricKit
import CryptoKit
import Combine

/// Crash, hang and resource-exception reports from real devices.
///
/// **Why MetricKit and not Crashlytics or Sentry.** This app is built entirely
/// on CI with no Mac in the loop. Every third-party crash SDK wants a build
/// phase that uploads dSYMs plus an account whose credentials would have to
/// live in CI secrets, and it wants a version-resolved package — which this
/// project has already lost CI runs to (see the Stripe 26.0.0 note in
/// project.yml, where a dependency's own source failed to compile against the
/// runner's Xcode). MetricKit is part of iOS: no package, no key, no build
/// phase, nothing that can fail to resolve.
///
/// **What it gives.** `MXCrashDiagnostic` carries the exception type, signal,
/// termination reason and a full call-stack tree for genuine crashes. The same
/// payload carries hangs, CPU exceptions and disk-write exceptions.
///
/// **What it does not give, stated plainly.** No immediacy and no dashboard.
/// iOS batches diagnostics and delivers them at most once every 24 hours, on
/// the next launch after the event, and only for people who have left
/// diagnostics sharing switched on. A crash surfaces tomorrow, not now. For a
/// handful of TestFlight testers that is the right trade; a public launch with
/// real volume is worth the dSYM plumbing of a real-time service.
///
/// Reports are kept on the device and shown in Settings → Diagnostics, so a
/// tester can send one without being talked through Console. `uploadHandler`
/// is where they start reaching the backend once an endpoint exists — nothing
/// accepts them today (checked against the live API 2026-10-26).
final class DiagnosticsStore: NSObject, ObservableObject {
    /// One diagnostic, flattened into something displayable and sendable.
    struct Report: Codable, Identifiable, Equatable {
        /// Content hash, not a fresh UUID — see `makeIdentifier`.
        let id: String
        /// "Crash", "Hang", "CPU", "Disk".
        let kind: String
        /// One line for the list.
        let summary: String
        /// The diagnostic's own JSON, including the call-stack tree. This is
        /// what actually diagnoses anything.
        let detail: String
        let receivedAt: Date
        /// Build the diagnostic came from, which is often not the build
        /// running now — a crash reported today can belong to yesterday's.
        let appVersion: String

        /// Stable across launches, because `pastDiagnosticPayloads` hands back
        /// the same diagnostics on every launch inside its retention window.
        /// A `UUID()` here would re-add the same crash every time the app
        /// started, and `hashValue` would not do either: Swift seeds its
        /// hashing per process, so it is not stable between launches.
        static func makeIdentifier(kind: String, appVersion: String, detail: String) -> String {
            let input = Data("\(kind)|\(appVersion)|\(detail)".utf8)
            return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        }
    }

    @Published private(set) var reports: [Report] = []

    /// Called for each newly-seen report. Hook the backend here.
    var uploadHandler: ((Report) async -> Void)?

    /// Oldest reports are dropped past this. Call-stack trees are large, and a
    /// device crashing in a loop should not fill its own disk with evidence.
    private static let maxReports = 25

    private let fileURL: URL

    override init() {
        self.fileURL = Self.storeURL()
        super.init()

        reports = Self.load(from: fileURL)
        MXMetricManager.shared.add(self)

        // Anything iOS already holds, rather than waiting up to 24 hours for
        // the next delivery to put a first row on the screen. Deduplicated by
        // content hash, so re-reading this on every launch is harmless.
        ingest(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func clear() {
        reports = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Ingest

    private func ingest(_ payloads: [MXDiagnosticPayload]) {
        let incoming = payloads.flatMap(Self.reports(from:))
        guard !incoming.isEmpty else { return }

        // MetricKit delivers on its own queue, and `reports` drives SwiftUI.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let known = Set(self.reports.map(\.id))
            let fresh = incoming.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }

            self.reports = Array(
                (fresh + self.reports)
                    .sorted { $0.receivedAt > $1.receivedAt }
                    .prefix(Self.maxReports)
            )
            self.persist()

            if let upload = self.uploadHandler {
                for report in fresh { await upload(report) }
            }
        }
    }

    private static func reports(from payload: MXDiagnosticPayload) -> [Report] {
        var result: [Report] = []

        for crash in payload.crashDiagnostics ?? [] {
            result.append(makeReport(kind: "Crash", summary: summarize(crash), diagnostic: crash))
        }
        for hang in payload.hangDiagnostics ?? [] {
            let seconds = hang.hangDuration.converted(to: .seconds).value
            result.append(makeReport(
                kind: "Hang",
                summary: String(format: "Unresponsive for %.1f seconds", seconds),
                diagnostic: hang
            ))
        }
        // Deliberately no type-specific properties for these two: they are
        // performance signals rather than failures, the JSON detail carries
        // everything anyway, and every extra API touched here is one more
        // signature that cannot be checked without a Mac.
        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            result.append(makeReport(kind: "CPU", summary: "Sustained high CPU use", diagnostic: cpu))
        }
        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            result.append(makeReport(kind: "Disk", summary: "Excessive disk writes", diagnostic: disk))
        }

        return result
    }

    private static func makeReport(kind: String, summary: String, diagnostic: MXDiagnostic) -> Report {
        let data = diagnostic.jsonRepresentation()
        let detail = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let version = diagnostic.metaData.applicationBuildVersion
        return Report(
            id: Report.makeIdentifier(kind: kind, appVersion: version, detail: detail),
            kind: kind,
            summary: summary,
            detail: detail,
            receivedAt: Date(),
            appVersion: version
        )
    }

    /// A crash's one-liner, built from whichever fields iOS actually filled
    /// in — they are all optional and a given crash rarely has them all.
    private static func summarize(_ crash: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let reason = crash.terminationReason, !reason.isEmpty { parts.append(reason) }
        if let type = crash.exceptionType { parts.append("exception \(type)") }
        if let code = crash.exceptionCode { parts.append("code \(code)") }
        if let signal = crash.signal { parts.append("signal \(signal)") }
        return parts.isEmpty ? "Crashed, no reason reported" : parts.joined(separator: " · ")
    }

    // MARK: - Persistence

    /// Application Support rather than Caches: the system may evict Caches
    /// under disk pressure, and a crash report evicted before anyone read it
    /// is the one thing this type exists to prevent.
    private static func storeURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("diagnostics.json")
    }

    private static func load(from url: URL) -> [Report] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Report].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension DiagnosticsStore: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        ingest(payloads)
    }

    /// Required by the protocol. Daily performance aggregates — launch times,
    /// battery, scroll hitches — with nowhere to send them and no screen that
    /// would be improved by showing them, so they are dropped rather than
    /// stored. The crash and hang half above is the part worth keeping.
    func didReceive(_ payloads: [MXMetricPayload]) {}
}
