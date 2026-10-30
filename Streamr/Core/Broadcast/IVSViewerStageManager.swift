import AmazonIVSBroadcast
import Foundation
import UIKit

/// The subscribe-side counterpart to IVSStageManager (host/publish-only).
/// Mirrors orca-nebula's `joinStageCommon`/SingleLive.tsx exactly: never
/// publishes anything of its own, always subscribes to every other
/// participant's audio+video. A real live-viewing feature — iOS never had
/// one; every episode shown to a viewer was VOD-only even while a host was
/// actually live (see PlayerView's prior doc comment).
///
/// Same standing caveat as IVSStageManager: method/type names below are
/// built from AWS's published Stages documentation and this file's own
/// prior experience (IVSImageDevice.previewView() turned out to be
/// no-arg-and-throwing on first real CI build, not the no-arg-non-throwing
/// assumed from docs alone) rather than a real local compile — there's no
/// Mac in this dev environment. `IVSStageRenderer`'s per-participant
/// stream-added/removed method names are the least certain part of this
/// file (the existing IVSStageManager has only ever exercised
/// `didChange connectionState:` from that protocol for real) — verify
/// against the actual SDK headers on first CI build and adjust names that
/// have drifted, same "flag the uncertainty rather than hide it" treatment
/// every other IVS file in this app already gets.
@MainActor
final class IVSViewerStageManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    /// Keyed by participant id — usually just the host, occasionally a
    /// second publisher too (the same guest-invite flow AddStreamCoordinator
    /// already builds for the host side). No mute/chat controls in this
    /// first pass — scoped to "can a viewer actually watch", matching how
    /// Alert Me and other features here shipped their core behavior first.
    @Published private(set) var remoteVideoViews: [String: UIView] = [:]
    @Published private(set) var errorMessage: String?
    /// True once every participant who was ever present has left — the
    /// simplest reliable "the stream ended" signal available without
    /// trusting an unverified host-id field on IVSParticipantInfo (the web
    /// app's STAGE_PARTICIPANT_LEFT handler compares against a known host
    /// id; this app only knows the host id from the token response, kept
    /// deliberately unused here to avoid a second unverified assumption).
    @Published private(set) var remoteParticipantLeft = false
    /// Viewer-side mute. Silences what's coming IN — it has no effect on what
    /// the broadcaster is sending, and no other viewer is affected.
    @Published private(set) var isMuted = false

    private var stage: IVSStage?
    private var hasHadParticipant = false
    /// Kept per participant so gain can be re-applied to late arrivals and
    /// dropped cleanly when someone leaves.
    private var remoteAudioStreams: [String: [IVSStageStream]] = [:]

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

    func leave() {
        stage?.leave()
        stage = nil
        remoteVideoViews = [:]
        remoteAudioStreams = [:]
        hasHadParticipant = false
        remoteParticipantLeft = false
        connectionState = .disconnected
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyGain()
    }

    func toggleMuted() {
        setMuted(!isMuted)
    }

    /// Gain, not a "muted" flag: a remote stream's `isMuted` is the
    /// BROADCASTER's state and is read-only to a subscriber, so the viewer's
    /// own mute has to be done by turning the incoming audio device down.
    /// 0 is silence and 1 is unchanged (the SDK clamps to 0...2).
    ///
    /// Re-applied on every attach as well as on toggle, so a participant who
    /// joins while you're muted doesn't arrive at full volume.
    private func applyGain() {
        let gain: Float = isMuted ? 0 : 1
        for streams in remoteAudioStreams.values {
            for stream in streams {
                (stream.device as? IVSAudioDevice)?.setGain(gain)
            }
        }
    }

    private func attachAudio(from streams: [IVSStageStream], participantId: String) {
        let audioStreams = streams.filter { $0.device is IVSAudioDevice }
        guard !audioStreams.isEmpty else { return }
        remoteAudioStreams[participantId, default: []].append(contentsOf: audioStreams)
        applyGain()
    }

    private func attachVideo(from streams: [IVSStageStream], participantId: String) {
        for stream in streams where stream.device is IVSImageDevice {
            guard let imageDevice = stream.device as? IVSImageDevice else { continue }
            do {
                // `.fit`, not the no-argument default (which fills, i.e.
                // crops). Live viewing doesn't go through AWS composition at
                // all — a viewer subscribes to the stage directly — so the
                // recording's `videoFillMode` has no effect here and this path
                // cropped a portrait host on its own. Same complaint as the
                // recorded clip (2026-10-11), different code path: the tile
                // this lands in is a fixed 16:9 frame with `.clipped()`, so a
                // filling preview lost the top and bottom of the picture.
                // Fitting letterboxes inside the tile instead.
                let preview = try imageDevice.previewView(with: .fit)
                remoteVideoViews[participantId] = preview
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension IVSViewerStageManager: IVSStageStrategy {
    nonisolated func stage(_ stage: IVSStage, shouldPublishParticipant participant: IVSParticipantInfo) -> Bool {
        false
    }

    nonisolated func stage(
        _ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo
    ) -> IVSStageSubscribeType {
        .audioVideo
    }

    nonisolated func stage(
        _ stage: IVSStage, streamsToPublishForParticipant participant: IVSParticipantInfo
    ) -> [IVSLocalStageStream] {
        []
    }
}

extension IVSViewerStageManager: IVSStageRenderer {
    nonisolated func stage(_ stage: IVSStage, didChange connectionState: IVSStageConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                self.connectionState = .connected
            case .connecting:
                self.connectionState = .connecting
            default:
                self.connectionState = .disconnected
            }
        }
    }

    nonisolated func stage(
        _ stage: IVSStage, participant: IVSParticipantInfo, didAdd streams: [IVSStageStream]
    ) {
        Task { @MainActor in
            self.hasHadParticipant = true
            self.remoteParticipantLeft = false
            self.attachVideo(from: streams, participantId: participant.participantId)
            self.attachAudio(from: streams, participantId: participant.participantId)
        }
    }

    nonisolated func stage(
        _ stage: IVSStage, participant: IVSParticipantInfo, didRemove streams: [IVSStageStream]
    ) {
        Task { @MainActor in
            self.remoteVideoViews.removeValue(forKey: participant.participantId)
            self.remoteAudioStreams.removeValue(forKey: participant.participantId)
        }
    }

    nonisolated func stage(_ stage: IVSStage, didLeave participant: IVSParticipantInfo) {
        Task { @MainActor in
            self.remoteVideoViews.removeValue(forKey: participant.participantId)
            self.remoteAudioStreams.removeValue(forKey: participant.participantId)
            if self.hasHadParticipant, self.remoteVideoViews.isEmpty {
                self.remoteParticipantLeft = true
            }
        }
    }
}

extension IVSViewerStageManager: IVSErrorDelegate {
    nonisolated func source(_ source: IVSErrorSource, didEmitError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}
