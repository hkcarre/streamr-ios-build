import Foundation

struct Endpoint {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    let path: String
    let method: Method
    var query: [URLQueryItem] = []
    var body: Encodable? = nil
    var requiresAuth: Bool = true
}

/// Endpoints confirmed by reading orca-nebula's src/services/*.ts and src/hooks/useAuth.ts,
/// and cross-checked live against https://api.streamr.nyc/v1 — see AppConfig.apiBaseURL.
enum API {
    enum Auth {
        static func login(email: String, password: String) -> Endpoint {
            Endpoint(path: "/onboarding/user/login", method: .post,
                     body: ["email": email, "password": password], requiresAuth: false)
        }

        static func signUp(firstName: String, lastName: String, email: String, password: String) -> Endpoint {
            Endpoint(path: "/onboarding/user/signUp", method: .post, body: [
                "firstName": firstName, "lastName": lastName, "email": email, "password": password
            ], requiresAuth: false)
        }

        static func forgotPassword(email: String) -> Endpoint {
            Endpoint(path: "/onboarding/forgotPassword", method: .post,
                     body: ["email": email], requiresAuth: false)
        }

        static func resetPassword(token: String, password: String) -> Endpoint {
            Endpoint(path: "/onboarding/resetPassword", method: .post,
                     body: ["token": token, "password": password], requiresAuth: false)
        }

        /// Confirmed against orca-nebula's src/hooks/useAuth.ts (socialLoginMutation) —
        /// both Google and Facebook already work against this contract live. Apple is
        /// NOT a proven loginType (the website has no Apple Sign-In) — see
        /// SocialLoginProvider.apple's doc comment.
        static func socialLogin(
            accessToken: String,
            loginType: SocialLoginProvider,
            email: String? = nil,
            userType: String? = nil,
            name: String? = nil,
            appleAuthCode: String? = nil
        ) -> Endpoint {
            Endpoint(path: "/onboarding/socialLogin", method: .post, body: SocialLoginPayload(
                accessToken: accessToken, loginType: loginType.rawValue, email: email,
                userType: userType, name: name, appleAuthCode: appleAuthCode
            ), requiresAuth: false)
        }
    }

    enum Discover {
        static func publicStreams(page: Int, limit: Int = 20) -> Endpoint {
            Endpoint(path: "/stream/public/list", method: .get, query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "type", value: "stream")
            ], requiresAuth: false)
        }

        /// Confirmed live 2026-09-03, reading orca-nebula's useAuth.ts
        /// directly — the Main Stream "Now Streaming" carousel's real
        /// source: the same public list, just filtered server-side to
        /// currently-live streams instead of client-side filtering.
        static func liveStreams(limit: Int = 12) -> Endpoint {
            Endpoint(path: "/stream/public/list", method: .get, query: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "type", value: "stream"),
                URLQueryItem(name: "streamType", value: "Live")
            ], requiresAuth: false)
        }

        /// Everything currently live, of EVERY type — no `type` filter.
        ///
        /// `liveStreams` above pins `type=stream` because that is what the
        /// public "Now Streaming" carousel should show. That filter hides a
        /// **Record** session which is also marked `Live` server-side, and a
        /// recording that didn't end cleanly is exactly as stuck as a stream
        /// that didn't: confirmed live 2026-10-14, where
        /// `type=stream&streamType=Live` returned 0 while `streamType=Live`
        /// alone returned the orphaned record session.
        ///
        /// LiveSessionMonitor uses this one, because the bar that ends a stuck
        /// session has to appear for recordings too — it is useless precisely
        /// in the case that produced it otherwise.
        static func allLiveStreams(limit: Int = 20) -> Endpoint {
            Endpoint(path: "/stream/public/list", method: .get, query: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "streamType", value: "Live")
            ], requiresAuth: false)
        }

        /// Finished, publicly listed episodes — the Main Stream page's
        /// "Recently Finished" section and the landing carousel's fallback.
        ///
        /// Previously sent NO `streamType` on the theory that an unfiltered
        /// call returns everything and could be filtered on `status` locally.
        /// That theory was wrong, confirmed against the live API 2026-10-20:
        /// omitting `streamType` returns `total: 0`, not everything. The
        /// parameter is effectively required, so the call had been yielding an
        /// empty list since it was written — which is why the signed-out
        /// landing carousel never appeared.
        ///
        /// `Ended` is one of only three values the server accepts (it answers
        /// "Type must be 'Live' or 'Created' or 'Ended'." to anything else) and
        /// is the right request to be making. It still returns empty today,
        /// because a finished broadcast is stored with status `Fulfilled` and
        /// the server's public filter does not map `Ended` onto it — a backend
        /// fix, raised as item 4 in streamr-backend-tasks.txt. The client-side
        /// `isWatchableReplay` filter stays as a guard either way, so this
        /// starts working the moment the server's mapping is corrected.
        static func recentStreams(limit: Int = 12) -> Endpoint {
            Endpoint(path: "/stream/public/list", method: .get, query: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "streamType", value: "Ended")
            ], requiresAuth: false)
        }

        static var categories: Endpoint {
            // Confirmed against the live API 2026-08-08: this actually requires auth
            // in production (returns {"message":"Unauthorized"} without a token),
            // despite looking public from the frontend source alone.
            Endpoint(path: "/category/allCategory", method: .get, requiresAuth: true)
        }
    }

    enum Shows {
        /// Confirmed live 2026-09-01: an empty body 400s with "Page is required" —
        /// this endpoint needs page/limit even though it's POST, not query params.
        /// No pagination UI exists yet for My Shows, so this fetches one generously
        /// large page rather than paginating; revisit if creators end up with more
        /// shows than `limit`.
        static func mine(page: Int = 1, limit: Int = 100) -> Endpoint {
            Endpoint(path: "/show/list", method: .post, body: ShowListPayload(page: page, limit: limit))
        }

        /// The Main Stream show list's real source, confirmed live
        /// 2026-09-03 — a flat `{data, total, page, limit, totalPages}`
        /// envelope (same shape as `mine()` above), not the usual
        /// `{data, pagination}`. `categoryId: ""` means "All Categories" —
        /// confirmed this is what the website itself sends, not an omitted
        /// field. Each `Show` in `data` comes back with `host`/`streamCount`
        /// populated (only true for this endpoint, see Show's doc comments)
        /// and, when `isFuture` is true, `streamScheduledTime`.
        static func listWithCategory(categoryId: String, isFuture: Bool, page: Int, limit: Int = 20) -> Endpoint {
            Endpoint(path: "/show/list-with-category", method: .post, body: ShowListByCategoryPayload(
                search: "", page: page, limit: limit, categoryId: categoryId, isFutured: isFuture
            ))
        }

        static func create(_ payload: ShowPayload) -> Endpoint {
            Endpoint(path: "/show/create", method: .post, body: payload)
        }

        static func update(id: String, _ payload: ShowPayload) -> Endpoint {
            Endpoint(path: "/show/update", method: .patch, body: ShowUpdatePayload(id: id, payload: payload))
        }

        static func delete(id: String) -> Endpoint {
            Endpoint(path: "/show/delete/\(id)", method: .delete)
        }
    }

    /// Confirmed live 2026-09-01 with a real auth token: multipart POST, response is
    /// `{"data": ["https://streamr-prod.s3.us-east-1.amazonaws.com/..."]}` — an ARRAY
    /// of URL strings (one per uploaded file), not `{"data": {"url": "..."}}` as
    /// originally guessed. Handled separately via APIClient.uploadImage rather than
    /// the generic JSON `request` since it needs multipart/form-data, not JSON.
    enum Media {
        static let uploadPath = "/user/uploads"
    }

    /// Mirrors orca-nebula's src/services/shareStream.ts. Account-level, not gated
    /// behind being live — connect once here, then auto-share checkboxes during
    /// show/stream creation just reference what's already connected.
    ///
    /// `connect(provider:)` deliberately omits the web app's `popup`/`origin` query
    /// params — those exist so the popup window can `postMessage` back to
    /// `window.opener`, which has no iOS equivalent. Omitting them makes the backend
    /// fall back to its plain redirect path; the iOS app presents that URL in
    /// SFSafariViewController and re-fetches `connectedAccounts` when it's dismissed
    /// (DestinationsViewModel), mirroring the web app's own `verifyConnectedQuietly`
    /// fallback rather than trying to auto-complete the flow.
    enum Destinations {
        static var connectedAccounts: Endpoint {
            Endpoint(path: "/user/connected/accounts", method: .get)
        }

        /// Returns a RAW `{"url": "…"}` body, NOT the `{data:…}` envelope —
        /// confirmed live 2026-10-06 against a real session. Decode as
        /// `ConnectURLResponse.self`, never `APIResponse<ConnectURLResponse>`.
        /// The returned URL's `redirect_uri` points at the backend
        /// (`/v1/shareStream/callback/{provider}`) and its `state` carries the
        /// userId, so the connection is recorded server-side regardless of the
        /// client — which is why omitting the web app's `popup`/`origin` params
        /// is harmless, and why re-fetching `connectedAccounts` after the
        /// Safari sheet is dismissed is a sound way to detect completion.
        static func connect(_ provider: DestinationProvider) -> Endpoint {
            Endpoint(path: "/shareStream/connect/\(provider.rawValue)", method: .get)
        }

        /// Returns `{"message": "youtube disconnected"}` — no `data` key at all,
        /// so only the message is meaningful (confirmed live 2026-10-06).
        static func disconnect(_ provider: DestinationProvider) -> Endpoint {
            Endpoint(path: "/shareStream/disconnect/\(provider.rawValue)", method: .get)
        }

        /// Confirmed to exist (connectWithCallBack in shareStream.ts) but unused by
        /// the current web UI, which relies on the popup + postMessage path instead.
        /// Wired here for completeness; not called by the v1 iOS connect flow.
        static func callback(_ provider: DestinationProvider, code: String, state: String) -> Endpoint {
            Endpoint(path: "/shareStream/callback/\(provider.rawValue)", method: .get, query: [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: state)
            ])
        }

        /// Only meaningful once Facebook is connected (page picker) — fast-follow,
        /// not required for the initial connect/disconnect screen.
        static var facebookPages: Endpoint {
            Endpoint(path: "/shareStream/facebook/pages", method: .get)
        }
    }

    /// Confirmed by reading orca-nebula's src/services/liveStream.ts and the
    /// stream-creation wizard (Steps/step1-3.tsx) directly.
    enum Streams {
        static func generateVideoUploadURL(fileName: String, fileType: String) -> Endpoint {
            Endpoint(path: "/stream/generate-video-url", method: .post, body: GenerateVideoURLPayload(
                fileName: fileName, fileType: fileType
            ))
        }

        static func createStage(_ payload: StageCreatePayload) -> Endpoint {
            Endpoint(path: "/stream/create-stage", method: .post, body: payload)
        }

        enum StageRole: String, Encodable {
            case publish = "PUBLISH"
            case subscribe = "SUBSCRIBE"
        }

        /// Mints an AWS IVS stage participant token. `role: .publish` for the
        /// host (and for a second-publisher guest, using the same shared
        /// link — see AddStreamStagingView); `.subscribe` for viewers, not
        /// used by this app yet (watch-side playback is out of scope).
        /// Pass `stageArn` whenever it's available — the website always does.
        /// Optional only because one caller fetches a token right after
        /// create-stage and may not have threaded it through yet.
        static func getToken(streamId: String, role: StageRole, stageArn: String? = nil) -> Endpoint {
            Endpoint(path: "/stream/get-token", method: .post, body: GetTokenPayload(
                stageArn: stageArn, role: role.rawValue, streamId: streamId
            ))
        }


        /// The real source of the guest-invite link's `roomArn` — confirmed
        /// live 2026-09-02 by reading orca-nebula's step3.tsx directly: the
        /// website only reaches for `create-stage`'s own `data.roomArn` as a
        /// first choice (which the live backend has never actually sent —
        /// confirmed absent from a real create-stage response), then always
        /// falls back to this call. `get-token` was wrongly assumed to be
        /// this app's source for `roomArn` before — it's a different AWS
        /// IVS **chat** room ARN entirely, unrelated to the stage token.
        /// Called only for `type == .record`, once the stage join succeeds —
        /// the one real server-side difference between Stream and Record.
        /// (Confirmed 2026-10-07 that the website's live-stream page never
        /// calls this, so the Stream path genuinely doesn't need it.)
        ///
        /// `stageArn` was missing from this call until 2026-10-07 — the website
        /// has always sent both fields (orca-nebula
        /// `src/services/liveStream.ts`, `startRecording`), so a recording
        /// started from iOS was very likely never associated with its stage.
        static func startRecording(stageArn: String, streamId: String) -> Endpoint {
            Endpoint(path: "/stream/startRecording", method: .post,
                     body: StageStreamPayload(stageArn: stageArn, streamId: streamId))
        }

        /// Ends the stream SERVER-side, which is what moves it into the
        /// "Processing" state and in turn triggers publishing to connected
        /// external platforms.
        ///
        /// Leaving the IVS stage (`IVSStageManager.leave()`) only tears down
        /// the local connection — the backend has no idea the broadcast
        /// finished. The iOS End Stream button did exactly that and nothing
        /// else, which is why streams never reached Processing and external
        /// publishing appeared broken (reported 2026-10-07).
        static func endStream(stageArn: String, streamId: String) -> Endpoint {
            Endpoint(path: "/stream/end", method: .post,
                     body: StageStreamPayload(stageArn: stageArn, streamId: streamId))
        }

        // MARK: Guest publishing
        //
        // A host invites a guest by sharing a link the app already builds:
        //   https://streamr.nyc/livestream?stageArn=…&streamId=…&role=PUBLISH&roomArn=…
        //
        // That link is a WEBSITE url, and orca-nebula's `App.tsx` returns
        // <MobileDesktopOnlyScreen /> for any viewport ≤1023px across every
        // route — so a guest who opens the invite on a phone has no way in at
        // all (confirmed 2026-10-08). These three endpoints are what let the
        // iOS app accept an invite itself.

        /// Registers the signed-in user as the stream's guest publisher.
        /// Errors when a guest is already attached — the website surfaces that
        /// as "Already a guest has been joined."
        static func guestJoin(streamId: String, userId: String) -> Endpoint {
            Endpoint(path: "/stream/guest/user", method: .post,
                     body: GuestJoinPayload(streamId: streamId, userId: userId))
        }

        /// Whether a guest has already taken the slot. Checked before
        /// registering so the guest gets a clear message instead of a raw
        /// server error.
        static func checkGuest(streamId: String) -> Endpoint {
            Endpoint(path: "/stream/check-guest/\(streamId)", method: .get)
        }

        /// The guest's counterpart to `/stream/end` — note it is NOT
        /// `/stream/end`: a guest leaving must not end the host's broadcast.
        /// The website's `guestEnd` posts to this path despite the name
        /// suggesting otherwise.
        static func guestLeft(streamId: String) -> Endpoint {
            Endpoint(path: "/stream/second-publisher-left/\(streamId)", method: .post)
        }

        /// Host/guest-side IVS chat auth. WRAPPED — the token is the envelope's
        /// `data` as a bare string (orca-nebula `ChatArea.tsx:46`
        /// `setChatToken(res.data)` where `res` is already the body), so decode
        /// as `APIResponse<String>`.
        static func chatToken(roomArn: String, userId: String) -> Endpoint {
            Endpoint(path: "/stream/chat-token", method: .post,
                     body: ChatTokenPayload(roomArn: roomArn, userId: userId))
        }

        /// Viewer-side equivalent. Separate endpoint because a viewer gets
        /// send-restricted capabilities, so don't substitute one for the other.
        static func viewerChatToken(roomArn: String, userId: String) -> Endpoint {
            Endpoint(path: "/stream/viewer/chat-token", method: .post,
                     body: ChatTokenPayload(roomArn: roomArn, userId: userId))
        }

        static func chatRoom(streamId: String) -> Endpoint {
            Endpoint(path: "/stream/chat-room", method: .post, body: StreamIdPayload(streamId: streamId))
        }

        /// Confirmed by reading orca-nebula's real player source directly
        /// (services/viewerStream.ts, SingleLive.tsx, SingleStream.tsx,
        /// WatchLive.tsx) — the viewer-side counterpart to the create/publish
        /// endpoints above. Never hit live (same standing caveat as
        /// StageTokenResponse/GenerateVideoURLResponse below).
        static func viewerList(page: Int, limit: Int = 20) -> Endpoint {
            Endpoint(path: "/stream/viewer/list", method: .get, query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "type", value: "stream")
            ])
        }

        static func viewerDetail(id: String) -> Endpoint {
            Endpoint(path: "/stream/viewer/details/\(id)", method: .get)
        }

        /// Mints a SUBSCRIBE-role AWS IVS stage token for watching a live
        /// episode — confirmed live 2026-10-04 against a disposable test
        /// "stream"-type episode. A different endpoint and payload shape
        /// from the host-side getToken above (stageArn/role/streamId here,
        /// not just streamId/role), reading orca-nebula's
        /// services/viewerStream.ts directly. Response is RAW with no
        /// `message`/`data` wrapper at all — {token, stageArn, coverPic,
        /// format, userId, streamStatus}. See IVSViewerStageManager for the
        /// join flow this token feeds (never subscribes/publishes — the
        /// host's own IVSStageManager is still publish-only).
        static func viewerToken(stageArn: String, streamId: String) -> Endpoint {
            Endpoint(path: "/stream/viewer/get-token", method: .post, body: ViewerTokenPayload(
                stageArn: stageArn, role: StageRole.subscribe.rawValue, streamId: streamId
            ))
        }

        /// A show's own episode list (Show Detail screen) — confirmed live
        /// 2026-09-03, reading orca-nebula's StreamLists.tsx directly.
        /// Standard `{message, data, pagination}` envelope; `data` decodes
        /// as the existing StreamItem — its embedded `showId` object isn't
        /// modeled (unneeded: the screen already knows which show it's on).
        static func byShow(showId: String, page: Int, limit: Int = 20) -> Endpoint {
            Endpoint(path: "/stream/streams/by-show-live-completed/\(showId)", method: .get, query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit))
            ])
        }

        /// Confirmed live 2026-09-28, reading YourStreams.tsx + StreamModel.tsx
        /// directly — the wireframe's "Edit Episode Details" screen. Only
        /// title/description/season/episode/tags are editable this way (matches
        /// the real edit form's fields exactly); artwork is show-level only
        /// (no per-episode field, see project-streamr-wizard-broadcast-build
        /// memory) and there's no type/format/category field in the real form
        /// either. Response is the standard {message, data} envelope.
        static func edit(id: String, title: String, description: String, season: String, episode: String, tags: [String]) -> Endpoint {
            Endpoint(path: "/stream/edit", method: .patch, body: EditStreamPayload(
                id: id, title: title, description: description, season: season, episode: episode, tags: tags
            ))
        }

        /// Confirmed live 2026-09-28 — {message} only, no `data` key at all
        /// (matches /show/delete's shape).
        static func delete(id: String) -> Endpoint {
            Endpoint(path: "/stream/delete/\(id)", method: .delete)
        }

        /// The wireframe's "Replace Audio (RSS Only)" — confirmed live
        /// 2026-10-02 against a disposable test show/episode, reading
        /// orca-nebula's ReplaceAudioModal.tsx + liveStream.ts directly first.
        /// Only touches the podcast RSS feed's audio track; the
        /// platform-hosted video is untouched (same copy as the website uses).
        /// Two-step upload, same presigned-S3 pattern as
        /// generateVideoUploadURL/S3Uploader (AddStreamCoordinator.beginUpload) —
        /// generate a URL with an audio fileType, PUT the file there, then
        /// POST the resulting fileUrl here. Response is a RAW object
        /// (`{message, replaceAudioRss}`), not the usual envelope. A
        /// not-found AND an unauthorized stream id both 404 with the same
        /// message ("Stream not found or unauthorized.") — can't distinguish
        /// the two cases from the response.
        static func replaceAudio(streamId: String, fileUrl: String) -> Endpoint {
            Endpoint(path: "/stream/replace-audio-direct/\(streamId)", method: .post, body: ["fileUrl": fileUrl])
        }
    }

    /// Confirmed live 2026-09-28, reading orca-nebula's services/plans.ts +
    /// services/stripe.ts directly.
    enum Subscription {
        static var activePlans: Endpoint {
            Endpoint(path: "/subscription/activeplans", method: .get)
        }
    }

    /// Same source as `Subscription` above. `stripe-config` and
    /// `purchaseFreePlan` are confirmed live (the latter already used
    /// end-to-end in earlier testing sessions to unblock a test account's
    /// subscription). `initialPayment`/`confirmPayment` are confirmed by
    /// reading the website's real source, but **not verified live** — the
    /// account's Stripe key is in live mode (real card charges), so this
    /// wasn't exercised against production the way everything else in this
    /// file has been. Both response types below are deliberately all-
    /// Optional so a shape surprise fails soft (a shown error) instead of
    /// crashing or silently corrupting state — verify against a real
    /// (ideally test-mode) purchase before trusting this path fully.
    enum Payment {
        static var stripeConfig: Endpoint {
            Endpoint(path: "/payment/stripe-config", method: .get)
        }

        static func purchaseFreePlan(planId: String) -> Endpoint {
            Endpoint(path: "/payment/purchaseFreePlan", method: .post, body: PlanIdPayload(planId: planId))
        }

        static func initialPayment(productId: String, paymentMethodId: String) -> Endpoint {
            Endpoint(path: "/payment/initial-payment", method: .post, body: InitialPaymentPayload(
                productId: productId, paymentMethodId: paymentMethodId
            ))
        }

        static func confirmPayment(paymentIntentId: String) -> Endpoint {
            Endpoint(path: "/payment/confirm-payment", method: .post, body: ConfirmPaymentPayload(
                paymentIntentId: paymentIntentId
            ))
        }

        /// Confirmed by reading accountSettings.ts directly — a GET despite
        /// being a mutating action (unusual, but that's what the site
        /// itself sends). Not live-verified (would actually cancel a real
        /// subscription; nothing to test it against safely without one).
        static var cancelSubscription: Endpoint {
            Endpoint(path: "/payment/subscription/cancel", method: .get)
        }

        /// Confirmed live 2026-10-01, reading PaymentMethod.tsx +
        /// payment-history.ts directly — the wireframe's "Payment" screen.
        /// Response is `{success, paymentMethods: [...]}`, NOT the
        /// `{data: {paymentMethods: [...]}}` the website's own
        /// `paymentMethodsData?.data?.paymentMethods` access implies — a
        /// real discrepancy between source and live behavior, caught by
        /// testing against production rather than trusting the read alone.
        static var paymentMethods: Endpoint {
            Endpoint(path: "/payment/payment-methods", method: .get)
        }

        /// Reuses the exact same card-entry -> createPaymentMethod flow as
        /// subscription checkout (see StripeCheckoutView) — same Stripe
        /// PaymentMethod id, different destination endpoint.
        static func addPaymentMethod(paymentMethodId: String, setAsDefault: Bool) -> Endpoint {
            Endpoint(path: "/payment/methods/add", method: .post, body: AddPaymentMethodPayload(
                paymentMethodId: paymentMethodId, setAsDefault: setAsDefault
            ))
        }

        static func removePaymentMethod(paymentMethodId: String) -> Endpoint {
            Endpoint(path: "/payment/methods/remove", method: .delete, body: RemovePaymentMethodPayload(
                paymentMethodId: paymentMethodId
            ))
        }

        /// Moves an existing PAID subscriber to a different paid plan.
        ///
        /// Confirmed to exist by reading orca-nebula directly
        /// (`services/accountSettings.ts` → `api.post("payment/subscription/upgrade", data)`,
        /// called from `plans.tsx:193` and `Subscription.tsx:98` with
        /// `{ newSubscriptionPlanId: planData._id }`). The website only takes
        /// this path when the current plan is NOT free; a free-plan user goes
        /// through the normal initial-payment flow instead, and this app
        /// mirrors that split — see PlansViewModel.
        static func upgradeSubscription(newPlanId: String) -> Endpoint {
            Endpoint(path: "/payment/subscription/upgrade", method: .post, body: UpgradePlanPayload(
                newSubscriptionPlanId: newPlanId
            ))
        }
    }

    /// Confirmed live 2026-09-28, reading orca-nebula's StreamLists.tsx
    /// directly — the wireframe's "Alert Me" feature. `showId`/`creatorId`
    /// are mutually exclusive in practice: toggling one off/on also flips
    /// the other's active state server-side (confirmed live — turning
    /// "creator" on for a show that had "show" active turned "show" off
    /// too), matching the wireframe's single-select "This show / This
    /// creator" tray rather than two independent toggles.
    enum User {
        static func alertDetails(creatorId: String, showId: String) -> Endpoint {
            Endpoint(path: "/user/toggle", method: .get, query: [
                URLQueryItem(name: "creatorId", value: creatorId),
                URLQueryItem(name: "showId", value: showId)
            ])
        }

        static func toggleAlert(userId: String, creatorId: String, showId: String, alertType: AlertType) -> Endpoint {
            Endpoint(path: "/user/toggle-alert", method: .post, body: ToggleAlertPayload(
                userId: userId, creatorId: creatorId, showId: showId, alertType: alertType.rawValue
            ))
        }

        /// Confirmed live 2026-09-28, reading Email&Password.tsx + its Yup
        /// schema directly. Returns HTTP 200 even on a wrong old password
        /// (`{success: false, message: "Your old password is incorrect."}`)
        /// — same "2xx doesn't mean success" shape as login-before-verify;
        /// callers must check `.success`, not just catch a thrown error.
        static func changePassword(oldPassword: String, newPassword: String, confirmNewPassword: String) -> Endpoint {
            Endpoint(path: "/user/changepassword", method: .put, body: ChangePasswordPayload(
                oldPassword: oldPassword, newPassword: newPassword, confirmNewPassword: confirmNewPassword
            ))
        }

        /// Already used all session as the disposable-test-account cleanup
        /// call (curl, never formalized until now) — response is just
        /// `{message}`, confirmed many times over.
        static var deleteAccount: Endpoint {
            Endpoint(path: "/user/account/delete", method: .delete)
        }

        /// Profile picture / cover photo / name / bio — step 2 of 2. Step 1 is
        /// `APIClient.uploadImage(data:filename:mimeType:)` (multipart POST to
        /// `API.Media.uploadPath`, form field `file`, responds `{data:[url]}`).
        /// This call persists the resulting URL against the user.
        ///
        /// **This is NOT `/user/updatePageSettings`.** That was used here until
        /// 2026-10-08 and never worked. Proven live against a disposable
        /// account:
        ///   PUT  /user/updatePageSettings {profilePic}
        ///     -> 400 {"message":"pageName is required"}, profilePic stays null
        ///   POST /user/complete-profile {firstName,lastName,bio,profilePic,coverPic}
        ///     -> 200, and profilePic/coverPic/bio all persist across re-login
        /// `/user/updatePageSettings` is the website's *page settings* form
        /// (`pageName`/`pageDesc` in orca-nebula `pageSettings.tsx`) and has
        /// nothing to do with photos.
        ///
        /// IMPORTANT: this endpoint takes the whole profile, so callers must
        /// pass the user's CURRENT firstName/lastName/bio alongside whatever
        /// they're changing. Sending only a photo would blank the rest.
        static func completeProfile(
            firstName: String,
            lastName: String,
            bio: String?,
            profilePic: String?,
            coverPic: String?
        ) -> Endpoint {
            Endpoint(path: "/user/complete-profile", method: .post,
                     body: CompleteProfilePayload(
                        firstName: firstName, lastName: lastName, bio: bio,
                        profilePic: profilePic, coverPic: coverPic
                     ))
        }

        /// Billing History on the Payment screen. Confirmed live
        /// 2026-10-01: `{success, data: [...], paymentMethod, pagination}`
        /// — standard envelope despite being a POST.
        static func transactions(page: Int, limit: Int = 10) -> Endpoint {
            Endpoint(path: "/user/transactions", method: .post, body: TransactionsPayload(page: page, limit: limit))
        }
    }
}

enum AlertType: String {
    case show
    case creator
}

struct ChatTokenPayload: Encodable {
    let roomArn: String
    let userId: String
}

struct GuestJoinPayload: Encodable {
    let streamId: String
    let userId: String
}

/// `/stream/check-guest/{id}` — the website reads `checkData?.guestJoined`
/// straight off the response body, so this is raw, not envelope-wrapped.
struct CheckGuestResponse: Decodable {
    let guestJoined: Bool?
}

/// Shared by `/stream/startRecording` and `/stream/end` — both take exactly
/// these two fields (confirmed against orca-nebula's liveStream.ts).
struct StageStreamPayload: Encodable {
    let stageArn: String
    let streamId: String
}

/// `POST /user/complete-profile`. firstName/lastName are always sent (the
/// endpoint treats them as required); bio/profilePic/coverPic are omitted when
/// nil rather than sent as null, so changing the avatar can't blank the cover.
struct CompleteProfilePayload: Encodable {
    let firstName: String
    let lastName: String
    let bio: String?
    let profilePic: String?
    let coverPic: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(profilePic, forKey: .profilePic)
        try container.encodeIfPresent(coverPic, forKey: .coverPic)
    }

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, bio, profilePic, coverPic
    }
}

struct SocialLoginPayload: Encodable {
    let accessToken: String
    let loginType: String
    let email: String?
    let userType: String?
    /// Apple only. The website sends the signed-in person's name alongside the
    /// token, because Apple reveals it exactly once — on the very first
    /// sign-in — and never again.
    let name: String?
    /// Apple only. The authorization code from the same credential, which the
    /// server exchanges with Apple. The website sends this on every Apple
    /// sign-in and the iOS app did not, which is the difference that matters:
    /// read out of the deployed bundle on 2026-10-20, `useAppleLogin` posts
    /// `{access_token, loginType:"Apple", name, appleAuthCode}`.
    let appleAuthCode: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case loginType, email, userType, name, appleAuthCode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(loginType, forKey: .loginType)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(userType, forKey: .userType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(appleAuthCode, forKey: .appleAuthCode)
    }
}

enum SocialLoginProvider: String {
    case google = "Google"
    case facebook = "Facebook"

    /// Confirmed supported 2026-10-20 by reading the DEPLOYED website, which
    /// signs in with this exact value. An earlier note here said the opposite,
    /// which came from checking a local clone of the web repo that is months
    /// behind what is actually running — the orca-nebula repository's only
    /// branch still sits at 30 July and has no Apple login in it at all.
    ///
    /// Apple needs two fields Google and Facebook do not: `appleAuthCode` and
    /// `name`. See SocialLoginPayload.
    case apple = "Apple"
}

struct ShowListPayload: Encodable {
    let page: Int
    let limit: Int
}

struct ShowListByCategoryPayload: Encodable {
    let search: String
    let page: Int
    let limit: Int
    let categoryId: String
    let isFutured: Bool
}

struct ShowPayload: Encodable {
    let name: String
    let description: String?
    let categoryId: String?
    let coverPic: String?
    let autoSharing: Bool
    /// Per-show platform selection (distinct from the `autoSharing` master
    /// toggle) — confirmed live 2026-10-02 round-tripping through
    /// /show/create and /show/update: the exact strings the backend expects
    /// are the DestinationProvider raw values ("youtube", "dailymotion",
    /// "twitch") plus the literal "RSS" for the always-available RSS feed
    /// row. Facebook deliberately left out of the per-show panel this pass —
    /// the website only adds "facebook" here together with a selected
    /// Facebook Page id, and there's no way to verify that page-picker flow
    /// live without a real connected Facebook account.
    let selectedProviders: [String]?
}

private struct ShowUpdatePayload: Encodable {
    let id: String
    let payload: ShowPayload

    enum CodingKeys: String, CodingKey {
        case id
        case name, description, categoryId, coverPic, autoSharing, selectedProviders
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(payload.name, forKey: .name)
        try container.encodeIfPresent(payload.description, forKey: .description)
        try container.encodeIfPresent(payload.categoryId, forKey: .categoryId)
        try container.encodeIfPresent(payload.coverPic, forKey: .coverPic)
        try container.encode(payload.autoSharing, forKey: .autoSharing)
        try container.encodeIfPresent(payload.selectedProviders, forKey: .selectedProviders)
    }
}

struct GenerateVideoURLPayload: Encodable {
    let fileName: String
    let fileType: String
}

/// Confirmed live 2026-09-02: the response is a RAW object
/// (`{uploadURL, fileUrl, fileName}`), NOT wrapped in the usual
/// `{data, message, ...}` envelope. Decode this type directly — wrapping it
/// in `APIResponse<GenerateVideoURLResponse>` silently "succeeds" into an
/// all-nil result instead of failing (every APIResponse field is Optional),
/// which is exactly what happened before this was fixed: real Upload
/// attempts always hit the generic "Couldn't start the upload." fallback.
struct GenerateVideoURLResponse: Decodable {
    let uploadURL: URL
    let fileUrl: URL
}

/// Confirmed live 2026-10-02 — raw object (`{message, replaceAudioRss}`),
/// no `data` wrapper. See API.Streams.replaceAudio's doc comment.
struct ReplaceAudioResponse: Decodable {
    let message: String
    let replaceAudioRss: URL
}

/// `stageArn` added 2026-10-08. The website has always sent all three
/// (orca-nebula `JoinStageFunctions.tsx` types it
/// `{stageArn, role, streamId}` and passes every one), while iOS sent only
/// `streamId` + `role`. Exactly the same omission that made `startRecording`
/// fail to associate a recording with its stage, so it is corrected here
/// pre-emptively rather than waiting for a symptom.
struct GetTokenPayload: Encodable {
    let stageArn: String?
    let role: String
    let streamId: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stageArn, forKey: .stageArn)
        try container.encode(role, forKey: .role)
        try container.encode(streamId, forKey: .streamId)
    }

    enum CodingKeys: String, CodingKey {
        case stageArn, role, streamId
    }
}

struct ViewerTokenPayload: Encodable {
    let stageArn: String
    let role: String
    let streamId: String
}

/// Confirmed live 2026-10-04 — raw object, no `message`/`data` wrapper at
/// all (not even `{message}` like most other raw endpoints in this app).
/// See API.Streams.viewerToken.
struct ViewerTokenResponse: Decodable {
    let token: String
    let stageArn: String
    let coverPic: String?
    let format: StreamFormat?
    let userId: String
    let streamStatus: String
}

struct StreamIdPayload: Encodable {
    let streamId: String
}

/// Confirmed live 2026-09-02: like generate-video-url, this is a RAW object
/// (`{guestUser, token, streamData: {...}}`), NOT wrapped in the usual
/// `{data, message}` envelope — decoding it as `APIResponse<StageTokenResponse>`
/// silently "succeeded" into an all-nil `data` every time, so the guest-invite
/// link and the stage join token never actually got set. There is no
/// `stageArn`/`roomArn` at the top level of this response at all (stageArn
/// lives nested in `streamData`, but this app doesn't need it from here —
/// `StreamItem.stageArn`, straight from create-stage, is the one confirmed
/// source; `roomArn` isn't in this response anywhere, see `API.Streams.chatRoom`).
struct StageTokenResponse: Decodable {
    let token: String
    /// The host's remaining plan allowance for this session.
    ///
    /// Confirmed live 2026-10-11 by reading orca-nebula directly:
    /// `JoinStageFunctions.tsx` returns the raw get-token response as
    /// `tokenData`, and `livestream.tsx:579` reads
    /// `tokenData.allowedStreamInfo.remainingSeconds` from it — so this is a
    /// sibling of `token`, not nested further. Optional because a plan with no
    /// limit omits it entirely.
    let allowedStreamInfo: AllowedStreamInfo?
}

/// Plan allowance, as reported by the backend.
///
/// Two endpoints return a version of this, confirmed live 2026-10-11 against a
/// disposable account on the free "Trial Subscription" plan (1 stream, 60 min):
///
///   - `POST /show/create` → `allowedStreams`, the fuller shape
///     (`allowed`, `remainingStreams`, `remainingSeconds`,
///     `totalStreamsAllowed`, `totalMinutesAllowed`, `planValidityEndsAt`,
///     `purchasedPlan`). This is the ONLY place the website reads it.
///   - `POST /stream/get-token` → `allowedStreamInfo`, which carries
///     `remainingSeconds` and is what this app can actually reach: the wizard
///     usually attaches an episode to an EXISTING show, so it never calls
///     `/show/create` and never sees the fuller shape.
///
/// **None of this is enforced server-side.** Verified 2026-10-11: on a plan
/// allowing exactly 1 stream, a second `create-stage` succeeded (and
/// provisioned a real IVS stage), an upload-type `create-stage` succeeded, and
/// afterwards `remainingStreams` still read 1 — the counter doesn't decrement
/// when streams are created. So `remainingStreams` cannot be used to detect
/// "out of streams" by any client, and this app deliberately doesn't try.
/// `remainingSeconds` IS usable, because it measures broadcast time the server
/// does track.
struct AllowedStreamInfo: Decodable {
    let allowed: Bool?
    let remainingStreams: Int?
    let remainingSeconds: Int?
    let totalStreamsAllowed: Int?
    let totalMinutesAllowed: Int?
}

/// Confirmed live 2026-09-02: raw object (`{message, roomArn}`), not
/// envelope-wrapped. `roomArn` is itself best-effort even on the website —
/// treat a failed/missing value as "no chat room yet", not an error.
struct ChatRoomResponse: Decodable {
    let roomArn: String?
}

/// Confirmed request shape (POST /stream/create-stage body) from
/// step3.tsx's submitFormLogic. `chat` is only ever encoded when
/// `type == .stream` — the real backend has no true three-state chat
/// setting, and Record/Upload never send this field at all (mirrors
/// ShowUpdatePayload's hand-written encode(to:) pattern above). The four
/// `var` fields at the bottom are upload-only — left nil for Stream/Record,
/// filled in after the S3 PUT succeeds for Upload (see AddStreamCoordinator).
struct StageCreatePayload: Encodable {
    let title: String
    let description: String?
    let guest: Bool
    let season: String
    let episode: String
    let categoryId: String?
    let tags: [String]
    let showId: String
    let scheduledTime: String?
    let type: VideoType
    let format: StreamFormat
    let chat: ChatVisibility?
    var videoURL: String?
    var videoSize: Int?
    var fileName: String?
    var durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case title, description, guest, season, episode, categoryId, tags, showId
        case scheduledTime, type, format, chat, videoURL, videoSize, fileName, durationSeconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(guest, forKey: .guest)
        try container.encode(season, forKey: .season)
        try container.encode(episode, forKey: .episode)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encode(tags, forKey: .tags)
        try container.encode(showId, forKey: .showId)
        try container.encodeIfPresent(scheduledTime, forKey: .scheduledTime)
        try container.encode(type, forKey: .type)
        try container.encode(format, forKey: .format)
        if type == .stream {
            try container.encodeIfPresent(chat, forKey: .chat)
        }
        try container.encodeIfPresent(videoURL, forKey: .videoURL)
        try container.encodeIfPresent(videoSize, forKey: .videoSize)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    }
}

struct PlanIdPayload: Encodable {
    let planId: String
}

struct InitialPaymentPayload: Encodable {
    let productId: String
    let paymentMethodId: String
}

struct ConfirmPaymentPayload: Encodable {
    let paymentIntentId: String
}

/// Raw response, not envelope-wrapped — matches purchaseFreePlan's already-
/// confirmed shape (`{success, message, purchasedPlan}`, no `data` key) and
/// the same pattern read directly in stripeCheckoutForm.tsx for both
/// payment endpoints. All-Optional per this file's Payment enum doc comment.
struct PurchasePlanResponse: Decodable {
    let success: Bool?
    let message: String?
}

/// Unconfirmed live (see API.Payment's doc comment) — reconstructed from
/// stripeCheckoutForm.tsx's field access (`initialResponse?.status`,
/// `.paymentIntentId`, `.success`). `status == "succeeded"` means the
/// backend already confirmed the charge (e.g. a previously-saved card) and
/// confirm-payment should still be called with the same paymentIntentId
/// (matches the web flow exactly, not skipped) to persist the subscription.
struct InitialPaymentResponse: Decodable {
    let success: Bool?
    let status: String?
    let paymentIntentId: String?
    let message: String?
}

struct ConfirmPaymentResponse: Decodable {
    let success: Bool?
    let message: String?
}

struct EditStreamPayload: Encodable {
    let id: String
    let title: String
    let description: String
    let season: String
    let episode: String
    let tags: [String]
}

struct AddPaymentMethodPayload: Encodable {
    let paymentMethodId: String
    let setAsDefault: Bool
}

struct UpgradePlanPayload: Encodable {
    let newSubscriptionPlanId: String
}

struct RemovePaymentMethodPayload: Encodable {
    let paymentMethodId: String
}

struct TransactionsPayload: Encodable {
    let page: Int
    let limit: Int
}

/// Raw response, not the `{data: {paymentMethods}}` shape the website's
/// own source implied — confirmed live 2026-10-01 (see
/// API.Payment.paymentMethods' doc comment).
struct PaymentMethodsResponse: Decodable {
    let paymentMethods: [SavedPaymentMethod]?
}

struct SavedPaymentMethod: Decodable, Identifiable {
    struct CardDetails: Decodable {
        let last4: String?
        let expMonth: Int?
        let expYear: Int?
        let isDefault: Bool?

        enum CodingKeys: String, CodingKey {
            case last4
            case expMonth = "exp_month"
            case expYear = "exp_year"
            case isDefault
        }
    }

    let id: String
    let card: CardDetails?
}

/// Billing History row — field names (createdAt/planName/
/// subscriptionPlan.name/amount/status) read from PaymentMethod.tsx's JSX,
/// not confirmed against a populated response (this app's test accounts
/// never carry real transaction history — would need a real charge to
/// produce one, which this codebase deliberately avoids against the
/// account's live Stripe key). No `id` field was used even by the website
/// itself (it keys its list by array index), so this isn't Identifiable —
/// render with an index-keyed ForEach instead.
struct Transaction: Decodable {
    let createdAt: String?
    let planName: String?
    let subscriptionPlan: PlanSummary?
    let amount: Double?
    let status: String?

    struct PlanSummary: Decodable {
        let name: String?
    }

    var displayPlanName: String {
        planName ?? subscriptionPlan?.name ?? "Subscription"
    }
}

struct ChangePasswordPayload: Encodable {
    let oldPassword: String
    let newPassword: String
    let confirmNewPassword: String
}

struct ToggleAlertPayload: Encodable {
    let userId: String
    let creatorId: String
    let showId: String
    let alertType: String
}

/// Confirmed live 2026-09-28 — both GET /user/toggle and POST
/// /user/toggle-alert return this exact shape (raw, not the usual
/// {data: ...} envelope; there IS a `data` key but it's the raw DB record,
/// not what the UI needs — these top-level fields are). Reused for both
/// endpoints since their responses are identical in shape.
struct AlertDetails: Decodable {
    let isActive: Bool
    let alertType: String?
    let isCreatorActive: Bool
    let isShowActive: Bool
}

/// Helper so `body:` literals like `["email": email]` satisfy Encodable without
/// hand-writing a struct per request.
extension Dictionary: @retroactive Encodable where Key == String, Value == String {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in self {
            try container.encode(value, forKey: DynamicKey(stringValue: key)!)
        }
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

struct EmptyBody: Encodable {}
