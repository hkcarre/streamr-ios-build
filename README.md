# Streamr iOS

Native SwiftUI client for Streamr — the livestreaming/podcasting platform whose
web frontends live in [`orca-nebula`](https://github.com/streamr-hub/orca-nebula)
(end-user app) and [`elephant-foundry`](https://github.com/streamr-hub/elephant-foundry)
(admin dashboard). This repo currently targets the **User** app surface (the
orca-nebula equivalent) — creator + viewer flows, not the admin dashboard.

This project was scaffolded on Windows, without access to Xcode. It has **not
been compiled or run yet** — you'll need a Mac (or the CI workflow below) to
build it for the first time and shake out any compile errors.

## Requirements

- Xcode 16+ (macOS)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Setup

This repo does **not** commit the `.xcodeproj` — it's generated from
[`project.yml`](project.yml) via XcodeGen, so the project structure stays a
readable, diffable YAML file instead of an opaque Xcode-managed blob.

```sh
brew install xcodegen
xcodegen generate
open Streamr.xcodeproj
```

## Backend

There is **one backend**, shared with both web apps — `https://api.streamr.nyc/v1`.
It's a single AWS EC2 instance (`stream-prod`, us-east-1) running React (web
build) + Node/Express + the database together, managed with PM2, confirmed by
its own developer (Gaurav): there's no separate dev/staging server, and the
plan was always for mobile to call this same API directly rather than get its
own backend. CORS is wide open (`Access-Control-Allow-Origin: *`), and the
response shape (`{message, data, pagination}`) matches this app's
`APIResponse<T>` exactly — confirmed live 2026-08-08 against
`GET /v1/stream/public/list`.

All three `Config/*.xcconfig` files (`Debug`/`Staging`/`Release`) point at
this same URL — there's nothing else to point them at. Local dev safety comes
from the app's own Debug-only demo mode (below), not a separate environment.

**If the mobile app ever needs a field or endpoint the existing API doesn't
have**: that requires a change to the backend's own codebase, which is not in
this GitHub org (not `streamr-hub/*` — ask Gaurav / whoever maintains it)
and follows its own dev-branch → test → merge-to-master → deploy process.
Coordinate there rather than assuming it's changeable from here.

**Infrastructure notes are deliberately not kept in this repository.** The
AWS account, instance, address and security-group audit used to live here;
they were removed on 2026-10-21 because this source is mirrored into a public
repository to use the free macOS runners that public repos get, and an app
repo is the wrong home for a description of the production attack surface.
Those notes now live outside version control - ask whoever holds the
infrastructure documentation.

## Architecture

```
Streamr/
  App/            Entry point, 3-tab bar (My Stream/Add Stream/My Account),
                   hamburger menu sheet, InlineAuthPrompt + AuthGate (login gating)
  Core/
    DesignSystem/ Brand colors/gradients/type (official Style Guide, see below),
                   SafariView (in-app browser for the legal/info pages)
    Networking/   APIClient, Endpoint definitions, config, S3Uploader (presigned
                   PUT with progress, for the Upload path below)
    Auth/         AuthManager (session state), Keychain-backed token storage,
                   Google/Facebook/Apple sign-in wrappers
    Broadcast/    IVSStageManager + CameraPreviewView — AWS IVS real-time
                   Stages integration for live broadcast (see below)
    Models/       Codable structs mirroring the backend's REST contract
  Features/
    Auth/         Login (always presented as a sheet, with Google/Facebook/Apple),
                   Signup, Forgot Password
    Stream/       StreamHomeView — owns the merged "My Stream" tab's nav chrome
                   and its in-page Main Stream/My Stream segmented toggle
    Discover/     Public live/VOD stream feed (GET /stream/public/list) — pure
                   content view, embedded as the Main Stream segment
    Shows/        Creator's Shows CRUD (POST /show/list, /create, /update,
                   /delete) — pure content view, embedded as the My Stream segment
    AddStream/    The episode-creation wizard behind the center tab (see below)
    Player/       Viewer-side episode screen (GET /stream/viewer/details/:id) —
                   status badge, description, tags, Follow/Like/Share; VOD
                   playback via AVPlayer once a real videoURL exists (see below)
    Destinations/ Connect/disconnect YouTube/Facebook/Dailymotion/Twitch for
                   auto-sharing (GET /user/connected/accounts, /shareStream/*)
    Account/      Profile + logout, Settings (Destinations, Terms & Conditions,
                   Privacy Policy)
StreamrTests/     Contract tests + offline unit tests (see below)
StreamrUITests/   XCUITest that walks the app and captures screenshots (see below)
```

**Nav**: 3 bottom tabs — **My Stream** hosts an in-page segmented Main
Stream/My Stream toggle (`StreamHomeView`) rather than two separate tabs; the
newest mobile wireframe's bottom-tab label alternates between "Main Stream"
and "My Stream" depending which screen is active, which reads as a
Figma-prototyping artifact (frame links wired to "whichever screen you're
not on") rather than an intentional spec — a single tab whose destination
depends on navigation history would be confusing. **Add Stream** (center)
never navigates — tapping it snaps back to whichever tab you were on and
presents the episode-creation wizard instead (SwiftUI's `TabView` has no
native non-navigating action-tab support, so `MainTabView`'s
`onChange(of: selectedTab)` does the snap-back). **My Account** is unchanged
from before, just relabeled to match the wireframe. The hamburger
(Privacy/About/Help/Log Out) stays on the Main Stream segment, matching
where it lives on the website; Dashboard is dropped since My Account already
reaches the same place.

**Contract tests** (`StreamrTests/ContractTests.swift`) call `api.streamr.nyc` directly
(bypassing demo mode) and assert the response shape still matches this app's models —
e.g. that `/stream/public/list` still returns `{message, data, pagination}`, and that
`/category/allCategory` still requires auth (the thing that turned out to be wrong when
checked by hand — this exists so the next drift gets caught by CI, not a user). They
only cover read-only, non-mutating public endpoints, deliberately — they don't create
real users/shows on every CI run.

**The mutating auth/CRUD endpoints were manually verified live 2026-09-01**, with a
real disposable test account (created, verified via a real email link, used, then
deleted via `DELETE /user/account/delete` — nothing left behind in production). This
was the single biggest open gap in the project up to this point; it found and fixed
four real bugs no amount of reading source code would have caught:
- **Signup does not log you in.** `POST /onboarding/user/signUp`'s `data` is just the
  new user's bare ID string, not a `User` object — no token at all. The real flow is
  signup → check email → click the verify link → **then** log in separately.
  `AuthManager.signUp` and `SignupView` now reflect this (a "check your email" success
  state instead of auto-authenticating); previously this would have hit `Login()`'s
  User-decode path with a string and just... broken, at the first real signup.
- **A 2xx status doesn't guarantee the expected shape.** Logging in before verifying
  returns **HTTP 200** with a *different* `data` shape and a genuinely useful message
  ("Please verify your email.") — `APIClient.decode` now falls back to surfacing that
  message on any decode failure instead of a generic "unexpected response" error,
  which fixes this case and should improve error messages generally.
- **`POST /show/list` requires `page`/`limit`** in the body even though it's a POST,
  not query params — an empty body 400s with "Page is required". This means **My
  Shows was silently broken against production this whole time** (always fell through
  to demo data / a raw error) until this was fixed.
- **`POST /user/uploads` returns `{"data": ["url"]}`** — an array of strings, not
  `{"data": {"url": "..."}}` as originally guessed. Fixed in `APIClient.uploadImage`.

Also confirmed: `POST /show/create` requires `coverPic` (its error says "thumbnail",
the field name is still `coverPic`) — `CreateEditShowViewModel` now enforces this
client-side for `.create` (not `.edit`, which was confirmed to work fine without
re-sending a photo). `PATCH /show/update` and `DELETE /show/delete/:id` matched
existing assumptions exactly, no changes needed there.

**No hard login wall**: since `/stream/public/list` needs no auth, guests land
straight on Main Stream — same pattern as Twitch/YouTube (browse first, log in
when you need to act). `Shows` and `Account` are wrapped in `AuthGate`,
which shows a short prompt + "Log In" button instead of their content when
signed out; Main Stream also has a "Log In" button in its toolbar for guests.
`LoginView` is never the app's root anymore — it's always presented as a
sheet, dismisses automatically once login/signup succeeds (`AuthManager`'s
`isAuthenticated` flips, watched via `.onChange`).

**Auth**: JWT bearer token, same as the web apps — obtained from
`POST /onboarding/user/login`, stored in the Keychain (not UserDefaults —
the native equivalent of the web apps' `localStorage` usage), attached to
every authenticated request, cleared automatically on a 401 (mirrors the
axios response interceptor in both React apps).

**Design tokens**: the authoritative source is the official Style Guide (Drive
folder shared 2026-08-11, `Style Guide.pdf`) — primary green `#9AD0AF`,
warning gold `#FFC978`, coral `#D37778`, purple→blue background gradient
`#7A44B6 → #4768DA`, black/white. **Font is `Heebo`** per that guide — this
corrects an earlier best-effort guess (Montserrat, inferred from
`orca-nebula/src/style/css/style.css`) that turned out to be wrong; the web
app itself may be off-brand here, or mid-rebrand, worth raising with the
team. No Heebo font files are bundled yet — `Core/DesignSystem/Typography.swift`
falls back to the system font. Google Fonts has Heebo (OFL-licensed);
grabbing `.ttf` files from there, bundling under `Resources/Fonts/`, and
registering them in Info.plist under `UIAppFonts` is a follow-up. `#D37778`
is a documented core brand color but isn't used as a standalone UI color
anywhere yet (only buried inside the 5-color rainbow `premiumBorder`
gradient) — worth asking the team what it's meant to represent before
using it more prominently.

The app icon and in-app wordmark come from the official artwork folder
(Drive, shared 2026-08-11) rather than being generated from scratch: the
icon is `S logo square.png` (2000×2000, pre-made, S-mark centered on the
brand gradient) downscaled to 1024×1024 and flattened to opaque (App Store
requires no alpha channel) — see
`Streamr/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. The
in-app wordmark (`Logo.imageset`) uses that same folder's
`Streamr logo full scale.png`. (An earlier pass hand-cropped a mark from
`Streamr logo vector.png` at the repo root, supplied 2026-08-09, before the
official pre-made assets existed — that file is now superseded, not
deleted, in case it's still wanted for reference.) The official folder also
has a circular badge variant (`S logo circle.png`, 480×480) not currently
used anywhere — available if a circular treatment (avatar fallback, favicon)
is ever needed. The YouTube/Facebook/Dailymotion/Twitch/Spotify/Apple
Podcasts/iHeartRadio icons under `Destination*.imageset` are ported directly
from orca-nebula's `public/images/` rather than redesigned — they're
third-party trademarked marks, not Streamr's to redesign. No Amazon Music
asset exists on the website either, so it's left out of the badge row.

**`xcodegen generate` does not preserve `Streamr/Resources/Info.plist`'s
content — CONFIRMED 2026-09-01, this was a real live bug, not just a risk.**
A commit on 2026-08-30 (`82a972d`) stripped the camera/mic usage strings,
OAuth URL schemes, and `APIBaseURL`/`APIEnvironmentName` out of the tracked
file; it was restored the next day (`179bdc2`) assuming the tracked file was
the source of truth CI built from. It wasn't: sideloading a CI-built `.ipa`
onto a real device threw `AppConfig.missingAPIBaseURL` at login *after* that
restore, on a commit where the tracked file was correct. Parsing the actual
compiled `Info.plist` inside that `.ipa` (binary plist — `bplist-parser` via
`npm`, no Mac needed) proved it: every custom key was missing except the
four already declared in `project.yml`'s `targets.Streamr.info.properties`
(`CFBundleDisplayName`, `UILaunchScreen`, `UIApplicationSceneManifest`,
`ITSAppUsesNonExemptEncryption`), plus Xcode's own standard boilerplate.
`xcodegen generate` was silently discarding the tracked file's other keys on
**every single CI build**, not just after a bad commit — this had likely
been broken since `info.properties` was first added to `project.yml`, masked
the whole time by DEBUG mode's automatic mock-data fallback on every network
error. Fixed by moving every custom key into `project.yml`'s `info.properties`
(the block XcodeGen actually honors) — see its comment there. The physical
`Streamr/Resources/Info.plist` file still exists (XcodeGen's `info.path`
needs a target) but is not authoritative; it carries a comment saying so.

## Social login setup

Google Sign-In, Facebook Login, and Sign in with Apple are fully wired
(`Core/Auth/{Google,Facebook}AuthService.swift`, `AppleSignInCoordinator.swift`,
buttons in `LoginView`/`SignupView`) against the confirmed
`POST /onboarding/socialLogin` contract. Credential status as of 2026-08-31:

**Bundle ID corrected 2026-10-04**: the app had been building as
`com.streamrhub.ios` all along, but App Store Connect's actual registered app
record (Apple ID `6817412854`, "Streamr.nyc") uses `nyc.streamr.streamr` —
these must match exactly for any signed build to ever upload. Switched the
whole project to `nyc.streamr.streamr` (`project.yml`, `KeychainStore`'s
Keychain service string) rather than the other way around, since the App
Store Connect app record already existed and Bundle IDs aren't easily
changed there after the fact. Anything below referencing a bundle ID means
`nyc.streamr.streamr` now — not `com.streamrhub.ios`, despite what earlier
console setup (Facebook's iOS platform entry, if already added) may say.

1. **Facebook App ID — ✅ real value now in all three xcconfigs**
   (`25500805429596280`). Found by pulling it straight out of the live
   website's public JS bundle (`streamr.nyc/assets/login-*.js`) — App IDs are
   meant to be public-facing, not secret, so this is a legitimate way to get
   it, not SSHing into anything. Needs an **iOS platform entry** in Facebook
   Developer Console (app → Settings → Basic → Add Platform → iOS, bundle ID
   `nyc.streamr.streamr`) — if one was already added under the old
   `com.streamrhub.ios` bundle ID, it needs to be redone/added again under
   the correct one for login to actually work on a signed build.
2. **Facebook Client Token — ✅ real, in the user's local
   `Config/Secrets.xcconfig`** (gitignored, not shown here). Confirmed the
   web app doesn't need this value at all — its login flow (JS SDK OAuth
   redirect) never touches it, only native iOS/Android SDKs do.
3. **Google Client ID — still a placeholder.** The *iOS* client (a separate
   OAuth client type from whatever Web client already exists) needs to be
   created with bundle ID `nyc.streamr.streamr` — doesn't need to be in the
   same Google Cloud project the website's own client belongs to, any
   project with a configured consent screen works. Drop the resulting client
   ID and its reversed form into `GOOGLE_CLIENT_ID` /
   `GOOGLE_REVERSED_CLIENT_ID` in `Config/Secrets.xcconfig`.
4. **Apple**: Apple Developer portal → confirm "Sign in with Apple" is
   enabled on the `nyc.streamr.streamr` Identifier record (the entitlement
   file, `Streamr/Resources/Streamr.entitlements`, is already wired in — this
   is the server-side-of-Apple half that record also needs).

**Sign in with Apple is client-side only right now.** The backend has never
seen an `"Apple"` `loginType` (the website only offers Google/Facebook) —
`SocialLoginProvider.apple`'s doc comment in `Endpoint.swift` flags this.
Expect a server error until backend adds support; the UI shows a friendly
"not available yet" message rather than the raw error in the meantime.

## Destinations (connect YouTube/Facebook/Dailymotion/Twitch)

Built as account-level connect/disconnect (`Features/Destinations/`,
reachable via Account → ⚙️ → Destinations) — matches how the website actually
works (`SocialMedia.tsx`): connect once, then show/stream creation just
checks off what's already connected, no live broadcast required.

Tapping "Connect" opens the backend's OAuth URL in `SFSafariViewController`;
there's no way to detect completion from inside that flow on iOS (the
website's popup + `window.postMessage` approach has no native equivalent), so
the screen just re-fetches `/user/connected/accounts` when the sheet is
dismissed — the same fallback (`verifyConnectedQuietly`) the website itself
relies on, so it needs no backend change to work.

**Not built**: an auto-completing flow via `ASWebAuthenticationSession` with
a custom URL scheme (`streamr://oauth-callback`) as the OAuth `returnTo`.
The website's `returnTo` is validated against a server-side allowlist that,
from the source available, only contains `/profile` and `/signup/profile` —
a custom scheme is almost certainly not on it. **Ask Gaurav** whether it can
be added before building this; wiring it against an unconfirmed allowlist
risks a session that silently hangs waiting for a redirect that never comes.

## Add Stream wizard & live broadcast

`Features/AddStream/` — behind the center tab. Confirmed against the real
web wizard source (`orca-nebula/src/pages/protected/stream/`), not guessed:
show selection/creation → Stream/Record/Upload + Video/Audio choice →
episode details (title, description, guest toggle, season/episode as fixed
1–50 dropdowns, tags as free comma-separated text, category, scheduled time,
and — **Stream type only** — a Public/Private chat toggle; the real backend
has no true three-state chat, "Off" just sends Private) → branches by type.

**Upload is the one fully real, end-to-end path**: `POST
/stream/generate-video-url` → presigned S3 PUT (`Core/Networking/S3Uploader.swift`,
progress-tracked via `URLSessionTaskDelegate`) → `POST /stream/create-stage`
with the upload URL/size/filename/duration filled in. `.fileImporter` is used
over `PhotosPicker` since audio files generally aren't in the Photos library.

**Stream/Record now build real live broadcast**, against AWS IVS real-time
Stages — confirmed to be the right target: the backend already dynamically
creates a fresh Stage per episode via `create-stage` (the AWS account has
~50 such stages already, all backend-created on demand), so there's no
separate "dev environment" to stand up — this just calls the same endpoints
the website already uses (`create-stage`, then `POST /stream/get-token` with
`role: PUBLISH` once the user reaches the staging screen and taps Go Live).
The AWS IVS iOS SDK (`AmazonIVSBroadcast`, product `AmazonIVSBroadcastStages`)
is vendored as a **local** SPM package (`Vendor/AmazonIVSBroadcast/Package.swift`,
downloaded from AWS's versioned manifest — AWS doesn't host a normal git-URL
package for it) — see `IVSStageManager`/`CameraPreviewView` under
`Core/Broadcast/`. "Record" goes through the identical publish pipeline as
"Stream," just additionally calls `POST /stream/startRecording` once joined
— it is **not** a local-record-then-upload flow.

**Guest invite**: the guest toggle (Stream/Record only) surfaces a native
`ShareLink` with the same `role=PUBLISH` URL pattern the website already
uses — first-come-first-served, one guest slot (confirmed: the backend
errors with "Already a guest has been joined" past that). The recipient
joins through the **website**, not a native "join as guest" screen in this
app — building that natively is its own scoped effort, not part of this pass.

**Known unconfirmed pieces, flagged rather than hidden:**
- `IVSStageManager`'s method/type names come from AWS's published
  documentation, not a real local compile (no Mac in this dev environment)
  — verify against the actual SDK headers on first CI build.
- `POST /stream/get-token`'s exact response field names (`StageTokenResponse`)
  and `POST /stream/generate-video-url`'s response envelope
  (`GenerateVideoURLResponse`) are best-effort — same "flag it, don't hide
  it" treatment this codebase already gives `UploadResponse`.
- No reconnection-on-network-drop handling, no simulcast/bitrate tuning, no
  in-app chat *display* (the Stream chat toggle only controls whether chat
  is enabled for viewers — building the viewer-side chat UI is watch-side
  work, out of scope here same as playback itself).
- **Cannot be tested in the iOS Simulator at all** — camera/mic capture
  needs real hardware. `create-stage`/`get-token`/`generate-video-url` are
  also mutating writes, deliberately **not** added to `ContractTests.swift`'s
  automated live-hitting pattern (which only covers safe, idempotent `GET`s)
  — verify with a manual QA pass on a real device + real account instead.

## Seeing the app without a Mac (demo mode + CI screenshots)

The app ships a **Debug-only demo mode**: a "Continue with Demo Data" button
on the login screen (and an automatic fallback if a real network call fails)
that populates the UI with sample data without needing a real account or
touching production data. This only exists in Debug builds (`#if DEBUG`) —
it compiles out of Release, and CI runs against it since there's no test
account configured yet.

Every push triggers `.github/workflows/ios-ci.yml`, which:
1. Builds the app on a macOS GitHub Actions runner (real compiler feedback,
   since none of this has been run through Xcode locally).
2. Runs both test targets in one `xcodebuild test` invocation (the scheme's
   `testTargets` includes both): `StreamrTests` (live contract tests +
   offline `CreateEditShowViewModelTests` artwork-validation boundary cases)
   and `StreamrUITests/ScreenshotTests.swift`, which launches the app, checks
   the hamburger menu, the My Stream/Main Stream segmented toggle, and the
   Add Stream tab's snap-back behavior, then taps through demo login → the
   Add Stream wizard's show/type-format/episode-details steps → My Account,
   capturing a screenshot of each screen (stops short of anything needing
   real camera access or a real network write).
3. Uploads those screenshots as a workflow artifact.

**To see the current UI from Windows**: go to the repo's
[Actions tab](https://github.com/streamr-hub/anchialine-ascent/actions),
open the latest **iOS CI** run, and download the **app-screenshots** artifact
(a zip of PNGs — open with any image viewer, no Mac needed). If screenshot
export ever fails (Xcode's `xcresulttool` export flags shift between
versions), the raw **xcresult-bundle** artifact is uploaded as a fallback,
and the workflow step will need a syntax tweak — check the run log for the
`xcresulttool` error.

For actually tapping around a live, interactive build from a browser (not
just static screenshots), a service like [Appetize.io](https://appetize.io)
can run the built `.app` in-browser — not set up here since it needs its own
account/API key; ask if you want that wired into CI as well.

## Roadmap (not yet built)

- ~~A real test account~~ — **done 2026-09-01**, see "Contract tests" above. Email/
  password signup → verify → login → show create/update/delete/upload are now
  confirmed against production, not just demo mode, and four real bugs found this
  way are fixed. **Still unverified**: Google/Facebook/Apple social login (needs
  real OAuth credentials — see "Social login setup"), Destinations' OAuth connect
  flow, and live broadcast past "the SDK initializes" (needs a Mac + physical device
  — camera/mic can't be exercised in the Simulator at all).
- ~~Watch Live / VOD playback~~ — **done 2026-10-04**: `PlayerView`
  (`Streamr/Features/Player/`) is a real screen now, reached by tapping a
  Discover card — status badge, title/description/tags, and a working Share
  button (native OS share sheet, same `ActivityShareSheet` the guest-invite
  flow uses — surfaces every share target installed on the device for free).
  VOD/replay plays back for real via `AVPlayer` once `GET
  /stream/viewer/details/:id` returns a `videoURL`. **Live in-progress
  viewing now also built** (2026-10-04, found missing by comparing against
  the live website rather than just the wireframe — the website has a
  dedicated SingleLive page this app never had an equivalent of): a real AWS
  IVS **subscribe** flow, `IVSViewerStageManager`
  (`Streamr/Core/Broadcast/`), joins the same stage the host publishes to via
  `POST /stream/viewer/get-token` (confirmed live 2026-10-04 against a
  disposable test episode — raw response, no `message`/`data` wrapper) and
  renders the host's video. No chat, no mute toggle, no multi-guest grid
  layout yet — scoped to "can a viewer actually watch", which didn't exist
  at all before. Same standing SDK-signature-uncertainty caveat as
  `IVSStageManager` (no Mac to compile locally) applies here too, doubly so
  for the per-participant stream-added/removed delegate methods, which
  `IVSStageManager` never had occasion to exercise for real. Follow and Like
  are UI-only, local state — **confirmed by reading orca-nebula's real
  source directly** (not just the minified bundle) that neither has a
  backend endpoint anywhere; `StreamDetailsCard`'s `actions` prop even has a
  code comment listing "mute, share, end stream, etc." with no follow/like
  ever wired in, on web either.
- A native "join as guest" screen — the guest-invite link currently routes
  through the **website** (same as the site's own guest-join flow), not a
  native in-app join experience. Building that is its own scoped effort.
- In-app chat *display* on the live/staging screen — the Stream type's chat
  toggle only controls whether chat is enabled for viewers; the chat UI
  itself is watch-side work, same scope boundary as playback above.
- Reconnection-on-network-drop handling and simulcast/bitrate tuning for the
  live broadcast path (see "Add Stream wizard & live broadcast" above for
  the full list of what's deliberately deferred there).
- Subscription plans + Stripe payment (StripePaymentSheet)
- Real Heebo font files (not Montserrat — see "Design tokens" above)
- Push notifications (scoped, waiting on Apple Developer account confirmation
  — the wireframes' "Alert Me" follow-notification button implies this)
- Full account Settings beyond Destinations/Legal — password change,
  subscription management, payment method, language, visibility, delete account
- Metrics (per-show)

**Built this pass, but with open items** — see "Social login setup",
"Destinations", and "Add Stream wizard & live broadcast" above for the details:
- ✅ Nav restructure (3-tab bar + segmented My Stream toggle + hamburger), real logo/app icon
- ✅ Google + Facebook Sign In (proven backend contract) + Sign in with Apple
  (client-side only, backend support unconfirmed)
- ✅ Connect YouTube/Facebook/Dailymotion/Twitch for auto-sharing (connect/disconnect
  works; the faster auto-completing redirect flow is blocked on a backend allowlist question) —
  now also wired into show creation itself (auto-share toggle opens Destinations
  if nothing's connected yet)
- ✅ Episode-creation wizard (show → type/format → episode details) against
  the confirmed real `create-stage` contract
- ✅ Upload path — fully real, end-to-end (S3 presigned upload + create-stage)
- ✅ Live broadcast (Stream/Record) — real AWS IVS Stages integration, but with
  several explicitly-flagged unconfirmed pieces (SDK signatures, two response
  shapes) and impossible to test without a real device — see the dedicated
  section above before treating this as verified, not just "built"
- ✅ Cover-art validation (square, 1400–3000px, ≤2MB, JPEG re-encode) — fixes a
  real pre-existing bug where HEIC photos were uploaded mislabeled as JPEG
