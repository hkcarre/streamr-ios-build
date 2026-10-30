import AmazonIVSBroadcast
import Foundation
import UIKit

/// Bridges AmazonIVSBroadcast's UIKit-era delegate/protocol API (IVSStage,
/// IVSStageStrategy, IVSStageRenderer, IVSErrorDelegate) into @Published
/// state a SwiftUI view can observe.
///
/// Method/type names here are built from AWS's published documentation
/// (docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/ios-publish-subscribe.html)
/// rather than compiling against the real SDK locally — there's no Mac in
/// this dev environment, so this has never been through a real Xcode build.
/// Verify every signature here against the actual SDK headers on first CI
/// build and adjust names that have drifted from what's documented — same
/// "flag the uncertainty rather than hide it" treatment this codebase
/// already gives unconfirmed backend response shapes.
@MainActor
final class IVSStageManager: NSObject, ObservableObject {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isPublishing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewView: UIView?
    @Published private(set) var isMicMuted = false
    /// True only when the device really does have both a front and a back
    /// camera to switch between, so the flip control is hidden rather than
    /// offered and then failing.
    @Published private(set) var canFlipCamera = false
    @Published private(set) var isUsingFrontCamera = true
    /// Live video from guests who have joined the stage, keyed by participant
    /// id — what makes the host see the people they invited.
    @Published private(set) var guestVideoViews: [String: UIView] = [:]

    private var stage: IVSStage?
    private var localStreams: [IVSLocalStageStream] = []

    /// Held for the whole lifetime of this manager, NOT created inline where
    /// the devices are listed.
    ///
    /// `IVSDeviceDiscovery` owns the devices it hands out; a temporary instance
    /// is released the moment `discoverLocalStreams()` returns, which is a
    /// documented way to end up with camera and microphone objects whose
    /// backing capture session has gone away — a preview that stays black being
    /// the visible result. AWS's own sample keeps it as a stored property for
    /// exactly this reason.
    private let deviceDiscovery = IVSDeviceDiscovery()

    /// Kept so the input source can be changed after discovery (front/back
    /// flip), which needs the live device, not just its published stream.
    private var camera: (any IVSCamera)?

    /// Brings the camera up WITHOUT joining a stage, so the host can frame
    /// themselves before going live.
    ///
    /// Previously `previewView` was only ever populated from
    /// `discoverLocalStreams()`, which the SDK calls from
    /// `streamsToPublishForParticipant` — i.e. only once a stage join was
    /// already underway. So the staging screen showed an empty black rectangle
    /// right up until the moment you were broadcasting, which is exactly
    /// backwards: reported 2026-10-11 as "Stream/Record: no preview until video
    /// starts". Device discovery is idempotent (`discoverLocalStreams` returns
    /// the cached list once built), so calling this early costs nothing and
    /// the same streams are handed to the SDK on join.
    func startPreview() {
        _ = discoverLocalStreams()
        // Also retried here, not only inside discovery: if building the
        // preview view throws the first time, `localStreams` is already
        // populated, so a second `discoverLocalStreams()` returns the cache
        // early and would never attempt the preview again.
        ensurePreview()
    }

    /// Builds the camera's preview view if there isn't one yet. Idempotent, so
    /// it's safe to call on every appearance.
    private func ensurePreview() {
        guard previewView == nil, let camera else { return }
        // `.fit` rather than the default: it letterboxes/pillarboxes instead of
        // cropping, so the host's preview shows the whole frame viewers get
        // rather than a cropped-to-fill version of it. Previewing a tighter
        // crop than you actually broadcast is worse than useless for framing a
        // shot.
        //
        // previewView() is a throwing call in the real SDK — it was assumed
        // non-throwing from documentation alone (no local compile possible in
        // this dev environment) and confirmed wrong on first CI build, exactly
        // the kind of drift flagged as a risk when this file was written.
        do {
            previewView = try camera.previewView(with: .fit)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func join(token: String) {
        do {
            let stage = try IVSStage(token: token, strategy: self)
            stage.errorDelegate = self
            stage.addRenderer(self)
            self.stage = stage
            connectionState = .connecting
            try stage.join()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops transmitting and tears the stage down. Safe to call at any time,
    /// including when nothing is connected — it only clears local state.
    ///
    /// Deliberately independent of whether the SERVER was successfully told the
    /// stream ended. Those are two different things, and conflating them is
    /// what trapped a host whose `/stream/end` call failed: the screen kept
    /// saying "Streaming Now" with no way to stop, because the teardown was
    /// gated behind a server call that kept failing.
    func leave() {
        stage?.leave()
        stage = nil
        localStreams = []
        previewView = nil
        camera = nil
        guestVideoViews = [:]
        canFlipCamera = false
        isUsingFrontCamera = true
        connectionState = .disconnected
        isPublishing = false
        isMicMuted = false
    }

    /// Brings `isPublishing` back in line with the stage's real connection
    /// state.
    ///
    /// `isPublishing` is only ever changed by an SDK callback. If the
    /// connection goes away without one — the app was suspended, the network
    /// dropped, the stage was closed server-side — the flag stays true and the
    /// UI insists you are on air when you are not. Called when the screen
    /// appears and when the app returns to the foreground.
    func reconcilePublishingState() {
        let reallyConnected = (stage != nil && connectionState == .connected)
        if isPublishing != reallyConnected {
            isPublishing = reallyConnected
        }
    }

    /// Mutes EVERY local stream, camera included — i.e. it takes you off air
    /// entirely, video and all. That is almost never what a "mute" button in a
    /// broadcast UI should do; use `setMicMuted(_:)` for the microphone alone.
    func setMuted(_ muted: Bool) {
        for stream in localStreams {
            stream.setMuted(muted)
        }
    }

    /// Microphone only — the camera keeps publishing, so viewers still see you
    /// while you're muted. `isMicMuted` is @Published so the button reflects
    /// the real device state rather than a separate copy in the view that
    /// could drift out of sync after a rejoin.
    func setMicMuted(_ muted: Bool) {
        for stream in localStreams where stream.device is IVSMicrophone {
            stream.setMuted(muted)
        }
        isMicMuted = muted
    }

    func toggleMicMuted() {
        setMicMuted(!isMicMuted)
    }

    /// Switches between the front and back camera, mid-broadcast or before it.
    ///
    /// Changing the camera's preferred input source keeps the same device and
    /// the same published stream, so this does not interrupt a live broadcast —
    /// which is why it's safe to leave enabled while on air.
    func flipCamera() {
        guard canFlipCamera else { return }
        selectCamera(front: !isUsingFrontCamera)
    }

    /// `isUsingFrontCamera` is only updated once the SDK confirms the change,
    /// so the button can't claim a flip that didn't happen. The completion is
    /// documented as always arriving on the main queue.
    private func selectCamera(front: Bool) {
        guard let camera else { return }
        let wanted: IVSDevicePosition = front ? .front : .back
        guard let source = camera.listAvailableInputSources().first(where: { $0.position == wanted }) else {
            return
        }

        camera.setPreferredInputSource(source) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.isUsingFrontCamera = front
                }
            }
        }
    }

    /// Explicit portrait publish resolution, rather than the SDK's `360x640`
    /// default.
    ///
    /// Signatures here are read from the real SDK headers (extracted from
    /// AmazonIVSBroadcast-Stages.xcframework 1.45.0 on 2026-10-11), not from
    /// documentation: `setSize:error:` requires both dimensions in 160...1280
    /// with at most 921,600 total pixels, so 720x1280 is the largest portrait
    /// frame the SDK accepts — exactly at the pixel ceiling.
    ///
    /// This publishes the phone's full portrait frame at the best resolution
    /// available. It does NOT by itself produce the "two black wings" framing
    /// asked for on 2026-10-11: how a portrait participant is placed inside a
    /// 16:9 recording is decided by the AWS IVS **composition** layout
    /// server-side (`videoFillMode`), which no client setting can override.
    /// See the handover notes — that one needs `CONTAIN` rather than `COVER`
    /// on the backend's composition config.
    private func makeVideoConfiguration() -> IVSLocalStageStreamConfiguration? {
        let configuration = IVSLocalStageStreamConfiguration()
        do {
            try configuration.video.setSize(CGSize(width: 720, height: 1280))
            return configuration
        } catch {
            // A rejected size must not stop the broadcast — fall back to the
            // SDK default by publishing with no explicit configuration.
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func discoverLocalStreams() -> [IVSLocalStageStream] {
        guard localStreams.isEmpty else { return localStreams }

        let devices = deviceDiscovery.listLocalDevices()
        var streams: [IVSLocalStageStream] = []
        let videoConfiguration = makeVideoConfiguration()

        for device in devices {
            if let camera = device as? IVSCamera {
                self.camera = camera
                let sources = camera.listAvailableInputSources()
                let hasFront = sources.contains(where: { $0.position == .front })
                let hasBack = sources.contains(where: { $0.position == .back })
                canFlipCamera = hasFront && hasBack
                // Open on the selfie camera. Whatever the SDK's default input
                // source happens to be, someone about to put themselves on air
                // expects to see their own face first — "they should be able to
                // see their faces or whatever they are recording" (2026-10-11).
                // Flipping to the back camera is one tap away.
                selectCamera(front: true)
                streams.append(IVSLocalStageStream(device: camera, config: videoConfiguration))
                ensurePreview()
            } else if let microphone = device as? IVSMicrophone {
                streams.append(IVSLocalStageStream(device: microphone))
            }
        }

        localStreams = streams
        return streams
    }
}

extension IVSStageManager: IVSStageStrategy {
    nonisolated func stage(_ stage: IVSStage, shouldPublishParticipant participant: IVSParticipantInfo) -> Bool {
        true
    }

    nonisolated func stage(
        _ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo
    ) -> IVSStageSubscribeType {
        // The host subscribes to guests, so an invited guest is visible and
        // audible on the host's own screen — asked for on 2026-10-14, "I would
        // like to be able to see both cameras side by side ... like a Zoom
        // call". This used to be `.none`, which meant a host could invite
        // someone and then have no idea whether they ever turned up.
        //
        // Note this only changes what the HOST sees. What viewers and the
        // recording see is decided by the server-side composition layout.
        .audioVideo
    }

    nonisolated func stage(
        _ stage: IVSStage, streamsToPublishForParticipant participant: IVSParticipantInfo
    ) -> [IVSLocalStageStream] {
        MainActor.assumeIsolated {
            discoverLocalStreams()
        }
    }
}

extension IVSStageManager: IVSStageRenderer {
    nonisolated func stage(
        _ stage: IVSStage, participant: IVSParticipantInfo, didAdd streams: [IVSStageStream]
    ) {
        // The SDK reports the LOCAL participant here too — `isLocal` is
        // "associated with the token used on this device to join the Stage".
        // Without this guard the host's own camera came back as a second tile,
        // so recording alone showed two identical screens (reported
        // 2026-10-15). The host's own picture is already on screen as the
        // local preview; this collection is guests only.
        guard !participant.isLocal else { return }

        Task { @MainActor in
            for stream in streams where stream.device is IVSImageDevice {
                guard let imageDevice = stream.device as? IVSImageDevice else { continue }
                do {
                    // `.fit` for the same reason the local preview uses it —
                    // a guest's whole frame, not a crop of it.
                    self.guestVideoViews[participant.participantId] = try imageDevice.previewView(with: .fit)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    nonisolated func stage(
        _ stage: IVSStage, participant: IVSParticipantInfo, didRemove streams: [IVSStageStream]
    ) {
        guard !participant.isLocal else { return }
        Task { @MainActor in
            self.guestVideoViews.removeValue(forKey: participant.participantId)
        }
    }

    nonisolated func stage(_ stage: IVSStage, didLeave participant: IVSParticipantInfo) {
        guard !participant.isLocal else { return }
        Task { @MainActor in
            self.guestVideoViews.removeValue(forKey: participant.participantId)
        }
    }

    nonisolated func stage(_ stage: IVSStage, didChange connectionState: IVSStageConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                self.connectionState = .connected
                self.isPublishing = true
            case .connecting:
                self.connectionState = .connecting
            default:
                self.connectionState = .disconnected
                self.isPublishing = false
            }
        }
    }
}

extension IVSStageManager: IVSErrorDelegate {
    nonisolated func source(_ source: IVSErrorSource, didEmitError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}
