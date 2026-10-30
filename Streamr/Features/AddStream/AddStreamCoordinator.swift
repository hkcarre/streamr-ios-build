import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AddStreamCoordinator: ObservableObject {
    enum Step: Equatable {
        case loadingShows
        case chooseOrCreateShow
        case typeAndFormat
        case episodeDetails
        case uploadProgress
        case inviteGuest
        case staging
        case done
    }

    @Published var step: Step = .loadingShows

    @Published private(set) var myShows: [Show] = []
    @Published var selectedShow: Show?

    @Published var type: VideoType = .stream
    @Published var format: StreamFormat = .video

    @Published var title: String = ""
    @Published var episodeDescription: String = ""
    @Published var guest: Bool = false
    @Published var season: String = "1"
    @Published var episode: String = "1"
    @Published private(set) var categories: [Category] = []
    @Published var selectedCategoryId: String?
    @Published var tagsText: String = ""
    @Published var scheduledTime: Date = Date()
    @Published var chatVisibility: ChatVisibility = .publicChat

    @Published var wizardError: String?
    /// Set when the show list couldn't be fetched, so the picker can offer a
    /// retry instead of claiming the creator has no shows. See `start()`.
    @Published private(set) var showsLoadError: String?
    @Published var isCreatingStage = false
    @Published private(set) var createdStreamId: String?
    /// Straight from create-stage's own response (`StreamItem.stageArn`) —
    /// confirmed live 2026-09-02 as the real source, not get-token (see
    /// fetchStageToken's doc comment).
    @Published private(set) var createdStageArn: String?
    @Published var guestInviteURL: URL?
    /// Fetched once, right after create-stage, and reused by the staging
    /// screen when actually joining — avoids requesting a second participant
    /// token for the same stage+role (unconfirmed whether the backend even
    /// allows that cleanly, so just don't need to find out).
    @Published private(set) var stageToken: String?

    /// Seconds of broadcast time this plan has left, from get-token's
    /// `allowedStreamInfo` (see AllowedStreamInfo). nil means the backend
    /// reported no limit, which is NOT the same as zero — see
    /// `streamTimeLimit`.
    @Published private(set) var remainingStreamSeconds: Int?

    /// The hard stop for this session, or nil for unlimited.
    ///
    /// The website gets this wrong in a way worth not copying: its timer
    /// treats `remainingSeconds <= 0` as "unlimited streaming" and returns
    /// early (orca-nebula `livestream.tsx:205-212`), so a host with their time
    /// fully used gets no limit at all instead of being stopped. Here nil
    /// means unlimited and 0 means out of time, which are kept distinct.
    var streamTimeLimit: Int? {
        guard let remainingStreamSeconds else { return nil }
        return max(remainingStreamSeconds, 0)
    }

    let uploader = S3Uploader()
    let stageManager = IVSStageManager()

    /// Republishes the stage manager's changes as this coordinator's own, so
    /// views observing the coordinator actually redraw when the broadcast
    /// changes.
    ///
    /// `stageManager` is a nested ObservableObject held by a plain `let`, and
    /// SwiftUI's dependency tracking only follows the object a view marks
    /// @ObservedObject/@StateObject. A @Published change inside a child reached
    /// through a property publishes nothing to the parent, so nothing redraws.
    /// Both wizard screens read the broadcast exclusively through
    /// `coordinator.stageManager` — the camera preview, status badge and Go
    /// Live/End button in AddStreamStagingView, and the Cancel button plus
    /// swipe-to-dismiss lock in AddStreamCoordinatorView — so all of them were
    /// rendering a snapshot frozen at whenever some *coordinator* property last
    /// changed.
    ///
    /// That single gap is behind several separately-reported symptoms:
    ///
    /// - The camera preview stayed a black rectangle. `previewView` going from
    ///   nil to a real UIView triggered no redraw, so `CameraPreviewView` was
    ///   never handed the view — reported 2026-10-11, "before someone records a
    ///   video or stream they should be able to see what they are recording".
    ///   `startPreview()` was working; nothing was watching it.
    /// - The badge kept reading "Streaming Now" after the connection dropped,
    ///   because `isPublishing` turning false redrew nothing — and
    ///   `reconcilePublishingState()`, added specifically to correct that flag,
    ///   corrected it without anything on screen noticing.
    /// - Errors set on the stage manager never appeared.
    ///
    /// PlayerView already had this right, observing its stage manager from a
    /// dedicated subview; the wizard never did. Forwarding here instead of
    /// adding @ObservedObject to each view fixes every current reader at once
    /// and can't be forgotten by the next screen that reads the stage.
    private var stageObservation: AnyCancellable?

    init() {
        stageObservation = stageManager.objectWillChange
            .sink { [weak self] _ in
                // IVSStageManager is @MainActor, so its publisher always fires
                // on the main actor — same assumption the SDK-callback path in
                // IVSStageManager already makes.
                MainActor.assumeIsolated {
                    self?.objectWillChange.send()
                }
            }
    }

    /// Set once `/stream/startRecording` has succeeded, so ending the stream
    /// can tell whether there is actually a recording in flight, and so a
    /// retry of Go Live can't start a second one.
    @Published private(set) var isRecording = false

    /// Latched true from the moment a session is started until it is ended —
    /// deliberately NOT the same thing as `stageManager.isPublishing`.
    ///
    /// `isPublishing` is the LOCAL IVS connection, and it goes false the
    /// instant the connection hiccups. The staging screen used to drive its
    /// whole appearance from it, so a dropped connection reverted the badge to
    /// "Ready" and the button to "Start Recording" — the screen claimed you had
    /// never started, while the session was still open server-side and still
    /// blocking you from creating another one. The only exit left was Cancel,
    /// which is exactly what was reported on 2026-10-14: "when I hit cancel
    /// then the stop button shows up".
    ///
    /// A session is running until the server is told otherwise. Connection
    /// health is a separate thing, shown separately.
    @Published private(set) var hasStartedSession = false

    /// Called once the stage join is under way, so Stop is on screen for the
    /// whole session rather than only while the connection happens to be up.
    func sessionDidStart() {
        hasStartedSession = true
    }

    /// The single in-flight end attempt, so concurrent callers coalesce onto it
    /// instead of each sending their own `/stream/end` — see finishLiveSession.
    private var endSessionTask: Task<Bool, Never>?

    /// Ends a live session properly: tell the SERVER first, then tear down the
    /// local stage. The one implementation of "stop broadcasting", shared by
    /// the Stop button and by the Cancel-while-live path, so the two can't end
    /// a stream differently.
    ///
    /// The brief wait mirrors the website, which pauses with the stream still
    /// flowing so the final frames finish uploading before `/stream/end` is
    /// called. Local publishing continues throughout — `leave()` only happens
    /// once the server has acknowledged.
    ///
    /// Returns false if the backend refused, so the caller can keep the host on
    /// screen with the error rather than dropping them somewhere that implies
    /// the episode was saved.
    @discardableResult
    /// Two screens can start this — the staging screen's Stop button and the
    /// toolbar's Cancel → "End & Save" — and each guards itself with its OWN
    /// in-flight flag, so neither could see the other's attempt. On top of that
    /// the 2.5s wait below holds the window open, and the time-limit timer and
    /// the interrupted-broadcast alert can both fire into it. Nothing stopped
    /// `/stream/end` being POSTed twice for one episode.
    ///
    /// Rather than refuse the second caller (which would surface as "couldn't
    /// end the stream" when the first attempt is succeeding), both await the
    /// same operation and get the same answer. One request, one answer, however
    /// many screens asked. The handle is cleared afterwards so a genuine retry
    /// after a failure still works.
    func finishLiveSession() async -> Bool {
        if let endSessionTask {
            return await endSessionTask.value
        }

        let task = Task { () -> Bool in
            try? await Task.sleep(nanoseconds: 2_500_000_000)

            guard await endStream() else { return false }

            hasStartedSession = false

            stageManager.leave()
            return true
        }
        endSessionTask = task

        let ended = await task.value
        endSessionTask = nil
        return ended
    }

    /// Stops transmitting WITHOUT requiring the server to agree.
    ///
    /// The escape hatch for when `/stream/end` keeps failing. Previously the
    /// teardown only ran after a successful server call, so a backend error
    /// left the host on air with a button that could not work — "a screen
    /// saying I'm streaming but I'm not, and I can't stop either", reported
    /// 2026-10-11.
    ///
    /// Going off air immediately is the right trade: the alternative is
    /// continuing to broadcast against the host's explicit wishes. The stream
    /// may stay Live server-side and the episode may not publish, which is why
    /// every caller says so plainly before using this.
    func stopBroadcastingLocally() {
        hasStartedSession = false
        stageManager.leave()
    }

    /// Lets the staging screen record the allowance from a token it fetched
    /// itself (the fallback path when the wizard's own prefetch failed), so the
    /// session limit applies either way.
    func applyAllowedStreamInfo(_ info: AllowedStreamInfo?) {
        guard let seconds = info?.remainingSeconds else { return }
        remainingStreamSeconds = seconds
    }

    /// Starts the server-side recording. Called right after the stage join
    /// succeeds, mirroring the website's order (create-stage -> get-token ->
    /// join -> startRecording).
    ///
    /// Deliberately non-throwing: a failure here must NOT tear down a
    /// broadcast that is already live and working. It surfaces as a banner so
    /// the host knows the episode won't be recorded or published, and can end
    /// and restart if that matters to them.
    func startRecording() async {
        guard let streamId = createdStreamId, let stageArn = createdStageArn else { return }
        guard !isRecording else { return }
        do {
            _ = try await APIClient.shared.request(
                API.Streams.startRecording(stageArn: stageArn, streamId: streamId),
                as: APIResponse<EmptyData>.self
            )
            isRecording = true
        } catch {
            wizardError = "You're live, but recording didn't start, so this episode won't be published afterwards. (\(error.localizedDescription))"
        }
    }

    /// Ends the stream SERVER-side. This is the call that moves the stream into
    /// Processing, which is what triggers publishing to connected platforms.
    ///
    /// Previously missing entirely: the End Stream button only left the IVS
    /// stage locally, so the backend never learned the broadcast had finished
    /// and the episode sat forever un-processed and unpublished.
    ///
    /// Returns true when the backend accepted it, so the caller can keep the
    /// host on the screen and show the error rather than silently dropping
    /// them into the "done" step believing everything worked.
    @discardableResult
    func endStream() async -> Bool {
        guard let streamId = createdStreamId, let stageArn = createdStageArn else {
            // Nothing was ever created server-side, so there's nothing to end.
            return true
        }
        do {
            _ = try await APIClient.shared.request(
                API.Streams.endStream(stageArn: stageArn, streamId: streamId),
                as: APIResponse<EmptyData>.self
            )
            isRecording = false
            return true
        } catch {
            wizardError = "Couldn't end the stream on the server, so it won't start processing or publish anywhere. Try again. (\(error.localizedDescription))"
            return false
        }
    }

    /// Always stops at the show step, whatever the count.
    ///
    /// **It used to skip that step when you had exactly one show**, selecting
    /// it and jumping to type/format. That was justified in this comment as
    /// matching the wireframe's "Add Stream (No streams yet)" framing, which
    /// misread it: "no streams yet" is the ZERO case, and the wireframe's
    /// step 1 for anyone with shows is a Show Name dropdown listing them
    /// alongside "+Add New Show".
    ///
    /// The cost was not a saved tap. "Add New Show" lives only in this step,
    /// and the My Stream toolbar's unlabelled "+" is the sole other route to
    /// it, so creating your first show removed the visible way to create a
    /// second — reported 2026-10-26 as "there was a screen create a show, why
    /// has it disappeared?". Skipping a step that is also the entry point to
    /// something else is what made it disappear.
    func start() async {
        step = .loadingShows
        showsLoadError = nil
        do {
            let response = try await APIClient.shared.request(API.Shows.mine(), as: APIResponse<[Show]>.self)
            myShows = response.data ?? []
        } catch {
            // "Couldn't load" is not "you have none". Treating them the same
            // told a creator with ten shows that they had none and pushed them
            // to create a duplicate — which then cost a real cover-image upload
            // and a real POST. The no-mock-data decision below is right; the
            // conflation was the bug.
            guard !error.isCancellation else { return }
            showsLoadError = "Couldn't load your shows. \(error.localizedDescription)"
            // No demo-data fallback here (unlike other DEBUG fallbacks in
            // this app) — confirmed 2026-09-01 as the cause of a real bug:
            // MockData.shows' ids ("show1"/"show2") aren't valid Mongo
            // ObjectIds, so picking one let the wizard sail all the way to a
            // real create-stage call that the backend then rejected with a
            // cryptic "show id must be a valid mongo id" error. An empty
            // list here routes to the same "create your first show" prompt
            // a real new user sees — always actionable, never misleading.
            myShows = []
        }

        step = .chooseOrCreateShow
    }

    func showCreated(_ show: Show) {
        myShows.insert(show, at: 0)
        selectedShow = show
        step = .typeAndFormat
    }

    func selectShow(_ show: Show) {
        selectedShow = show
        step = .typeAndFormat
    }

    func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        do {
            let response = try await APIClient.shared.request(API.Discover.categories, as: APIResponse<[Category]>.self)
            categories = response.data ?? []
        } catch {
            // No mock-data fallback here — same reasoning as
            // CreateEditShowViewModel.loadCategories(): this feeds straight
            // into create-stage's categoryId, and a fake MockData id would
            // be pickable but fail downstream instead of just being absent.
        }
    }

    func proceedToStaging() {
        step = .staging
    }

    func confirmTypeAndFormat() {
        // Chat only ever applies to the Stream type — reset to a sane
        // default so a stale Off/Private choice from a prior type selection
        // doesn't linger unseen.
        if type != .stream {
            chatVisibility = .publicChat
        }
        step = .episodeDetails
    }

    /// Free comma-separated entry, alphanumeric only, no count/length limit —
    /// confirmed as acceptable v1 scope directly by the wireframe's author.
    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }
    }

    private func buildBasePayload(showId: String) -> StageCreatePayload {
        StageCreatePayload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: episodeDescription.isEmpty ? nil : episodeDescription,
            guest: guest,
            season: season,
            episode: episode,
            categoryId: selectedCategoryId,
            tags: tags,
            showId: showId,
            scheduledTime: ISO8601DateFormatter().string(from: scheduledTime),
            type: type,
            format: format,
            chat: type == .stream ? chatVisibility : nil
        )
    }

    func submitEpisodeDetails() {
        wizardError = nil
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            wizardError = "Give your episode a name."
            return
        }

        switch type {
        case .upload:
            step = .uploadProgress
        case .stream, .record:
            Task { await beginLiveStage() }
        }
    }

    /// Stream/Record: the stage record itself is created for real here
    /// (title/season/tags/etc. are genuinely saved), then immediately
    /// followed by a token fetch — needed either way to build the guest
    /// invite link, and reused later so camera/mic permission (asked on the
    /// staging screen) doesn't gate getting a shareable link at all.
    private func beginLiveStage() async {
        guard let selectedShow else { return }
        isCreatingStage = true
        defer { isCreatingStage = false }

        do {
            let payload = buildBasePayload(showId: selectedShow.id)
            let response = try await APIClient.shared.request(
                API.Streams.createStage(payload), as: APIResponse<StreamItem>.self
            )
            guard let streamId = response.data?.id else {
                wizardError = response.message ?? "Couldn't create the stream."
                return
            }
            createdStreamId = streamId
            createdStageArn = response.data?.stageArn

            await fetchStageToken(streamId: streamId)
            step = guest ? .inviteGuest : .staging
        } catch {
            wizardError = error.localizedDescription
        }
    }

    /// Best-effort: a failed token fetch here shouldn't block the wizard —
    /// the staging screen falls back to fetching its own token if this one
    /// never landed.
    ///
    /// Confirmed live 2026-09-02, reading orca-nebula's step3.tsx directly
    /// (not guessed): `stageArn` for the guest-invite link comes from
    /// create-stage's own response (`createdStageArn`, above) — get-token's
    /// response has no `stageArn`/`roomArn` at all (it's `{guestUser, token,
    /// streamData}`, and `streamData.stageArn` is redundant with what
    /// create-stage already gave us). `roomArn` is a **different** AWS IVS
    /// **chat** room ARN, from its own `/stream/chat-room` endpoint — the
    /// website itself treats it as best-effort (falls back to an empty
    /// string in the link if this fails), so this does the same rather than
    /// blocking the invite link on it.
    private func fetchStageToken(streamId: String) async {
        do {
            let tokenInfo = try await APIClient.shared.request(
                API.Streams.getToken(streamId: streamId, role: .publish, stageArn: createdStageArn),
                as: StageTokenResponse.self
            )
            stageToken = tokenInfo.token
            remainingStreamSeconds = tokenInfo.allowedStreamInfo?.remainingSeconds
        } catch {
            // Swallowed deliberately — see doc comment above.
        }

        var roomArn = ""
        if let chatRoom = try? await APIClient.shared.request(
            API.Streams.chatRoom(streamId: streamId), as: ChatRoomResponse.self
        ), let value = chatRoom.roomArn {
            roomArn = value
        }

        // Same role=PUBLISH link pattern the website already uses —
        // first-come-first-served, one guest slot, matches confirmed
        // backend behavior. The recipient joins through the website, not a
        // native "join as guest" screen in this app (out of scope).
        //
        // Always build this, not just when `guest` was toggled on:
        // confirmed 2026-09-02 as a real gap — the only way to ever see
        // this link was that one-shot toggle on the episode-details screen
        // (easy to miss, and if you skipped it there was no way to invite
        // anyone later at all, even from the staging screen where "Go Live"
        // itself lives). Building it unconditionally means
        // AddStreamStagingView's own Invite Guest button always has
        // something to share.
        if let stageArn = createdStageArn {
            guestInviteURL = URL(
                string: "https://streamr.nyc/livestream?stageArn=\(stageArn)&streamId=\(streamId)&role=PUBLISH&roomArn=\(roomArn)"
            )
        }
    }

    /// True from the instant Share is tapped until the whole upload finishes,
    /// which is NOT the same window as `uploader.isUploading`.
    ///
    /// The Share button was disabled on `uploader.isUploading` alone, but that
    /// only goes true once the S3 PUT itself begins — and `beginUpload` makes a
    /// `generateVideoUploadURL` round trip first. During that gap the button
    /// was fully live, so a second tap (or an impatient double tap) ran the
    /// whole sequence again and created a second episode from one file.
    /// Reported 2026-10-11: "came thru twice on mobile and desktop — duplicate
    /// upload publish on mobile."
    @Published private(set) var isSubmittingUpload = false

    /// The one fully real, end-to-end path: presigned S3 URL -> raw PUT ->
    /// create-stage with the upload-only fields filled in.
    func beginUpload(localFileURL: URL) async {
        guard let selectedShow else { return }
        // Re-entrancy guard, not just a disabled button: the button is one way
        // in, but this closes the window regardless of how it's called.
        guard !isSubmittingUpload else { return }
        isSubmittingUpload = true
        defer { isSubmittingUpload = false }
        wizardError = nil

        do {
            let fileName = localFileURL.lastPathComponent
            let fileType = UTType(filenameExtension: localFileURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"

            // Confirmed live 2026-09-02: this response is a RAW object
            // ({uploadURL, fileUrl, fileName}), not wrapped in the usual
            // {data, message} envelope — the prior APIResponse<...>-wrapped
            // decode was silently "succeeding" into an all-nil APIResponse
            // (every one of its fields is Optional, so JSONDecoder doesn't
            // fail just because none of them were present) and always
            // hitting the "Couldn't start the upload." fallback. Found by
            // testing Upload on a real device — this endpoint had never
            // actually been exercised live before.
            let uploadInfo = try await APIClient.shared.request(
                API.Streams.generateVideoUploadURL(fileName: fileName, fileType: fileType),
                as: GenerateVideoURLResponse.self
            )

            try await uploader.upload(fileURL: localFileURL, to: uploadInfo.uploadURL, contentType: fileType)

            let asset = AVURLAsset(url: localFileURL)
            let duration = try? await asset.load(.duration)
            // `URLResourceValues.fileSize`, not `FileManager.attributesOfItem`.
            // The latter is backed by stat and sits in Apple's required-reason
            // "file timestamp" API category, which would have to be declared in
            // PrivacyInfo.xcprivacy — for a byte count the app only needs so it
            // can tell the backend how big the upload was. This reads the size
            // without touching that category, so there is nothing to declare.
            let fileSize = (try? localFileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize

            var payload = buildBasePayload(showId: selectedShow.id)
            payload.videoURL = uploadInfo.fileUrl.absoluteString
            payload.videoSize = fileSize
            payload.fileName = fileName
            payload.durationSeconds = duration?.seconds

            _ = try await APIClient.shared.request(
                API.Streams.createStage(payload), as: APIResponse<EmptyData>.self
            )
            step = .done
        } catch {
            wizardError = error.localizedDescription
        }
    }
}
