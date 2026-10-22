import Combine
import Foundation

/// Knows whether the signed-in user has a stream that is live RIGHT NOW, so
/// one End control can follow them around the app instead of being scattered
/// across screens where they happen to be a viewer.
///
/// Why this exists, from testing on 2026-10-14: "End stream is universal or on
/// many different pages — but does not appear during the live streaming event
/// which is when it should appear!" The wizard's own Stop button only exists
/// while the broadcast sheet is open. Dismiss that sheet, get a phone call,
/// force-quit, or simply reopen the app, and the host was live with no way to
/// stop — which is the same "stream stuck in On position" that keeps coming
/// back. Meanwhile an End Stream button sat on the watch screen, where you are
/// the audience, not the broadcaster; that one has been removed.
///
/// Source is the PUBLIC live list, not a per-user endpoint: it needs no auth,
/// it's the same list the landing carousel already shows (so what the host sees
/// matches what everyone else sees), and it carries `userId` and `stageArn` —
/// everything `/stream/end` needs.
@MainActor
final class LiveSessionMonitor: ObservableObject {
    /// The signed-in user's own currently-live stream, or nil.
    @Published private(set) var myLiveStream: StreamItem?
    @Published private(set) var isEnding = false
    @Published var errorMessage: String?

    private var userId: String?
    private var pollTask: Task<Void, Never>?

    /// Long enough not to hammer the API, short enough that a stream ended from
    /// the website or another device clears here without a relaunch.
    private let pollInterval: Duration = .seconds(45)

    func start(userId: String?) {
        guard self.userId != userId || pollTask == nil else { return }
        self.userId = userId
        pollTask?.cancel()

        guard userId != nil else {
            myLiveStream = nil
            pollTask = nil
            return
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        userId = nil
        myLiveStream = nil
    }

    func refresh() async {
        guard let userId else { return }
        do {
            let response = try await APIClient.shared.request(
                API.Discover.allLiveStreams(limit: 20), as: APIResponse<[StreamItem]>.self
            )
            // Filter on status as well as owner: `streamType=Live` is a
            // confirmed parameter, but a backend that ignored it would
            // otherwise hand every viewer a banner saying they're broadcasting.
            //
            // Covers Record sessions as well as Stream ones — see
            // API.Discover.allLiveStreams for why the carousel's endpoint was
            // the wrong source here.
            myLiveStream = (response.data ?? []).first {
                $0.ownerId == userId && $0.status == .live
            }
        } catch {
            // Silent: a dropped poll must not put an error in front of someone
            // who isn't broadcasting. A real failure surfaces when they act.
            guard !error.isCancellation else { return }
        }
    }

    /// Ends the live stream, the same way every other End does — `/stream/end`
    /// with the stage ARN and id, which moves it to Processing so it still
    /// publishes.
    @discardableResult
    func endLiveStream() async -> Bool {
        guard let stream = myLiveStream else { return true }
        guard let stageArn = stream.stageArn, !stageArn.isEmpty else {
            errorMessage = "This stream has no stage on record, so it can't be ended from here."
            return false
        }

        isEnding = true
        defer { isEnding = false }

        do {
            _ = try await APIClient.shared.request(
                API.Streams.endStream(stageArn: stageArn, streamId: stream.id),
                as: APIResponse<EmptyData>.self
            )
            myLiveStream = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
