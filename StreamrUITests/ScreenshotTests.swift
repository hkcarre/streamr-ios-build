import XCTest

/// Drives the app through its main screens and attaches a screenshot of each
/// to the test result bundle. This is the "see it from Windows" loop: CI runs
/// this on every push and the workflow exports the screenshots as a downloadable
/// artifact — no Mac or Simulator needed to see what the app currently looks like.
///
/// Deliberately does NOT set continueAfterFailure = false: if one screen isn't
/// reachable, we still want screenshots of whatever state the app got stuck in
/// instead of aborting blind. XCTFail still marks the run red so it's visible in CI.
final class ScreenshotTests: XCTestCase {
    func testCaptureKeyScreens() throws {
        let app = launchApp()

        // App now opens straight into the Hub tab as a guest, showing the Main
        // Stream segment by default — no login wall.
        //
        // Looked up as `app.buttons`, NOT `app.tabBars.buttons`: the stock tab
        // bar is hidden and replaced by StreamrTabBar, which is an ordinary
        // HStack of Buttons rather than a UITabBar, so no tabBars element
        // exists to query. These lookups still said `tabBars` after the custom
        // bar landed and would have failed the moment the stock bar was
        // actually hidden — which it wasn't until 2026-10-11, the same bug that
        // showed two bars stacked on top of each other in build 5.
        let streamTab = app.buttons["Hub"]
        guard streamTab.waitForExistence(timeout: 20) else {
            XCTFail("Should land on the Hub tab immediately, with no auth required")
            return
        }
        attach(app, name: "01-MainStream-Guest")

        // Hamburger menu opens as its own sheet, independent of the Log In
        // tap-through below — verify it opens and closes cleanly, then
        // continue the original flow via the segment's own "Log In" button.
        let hamburgerButton = app.navigationBars.buttons["line.3.horizontal"]
        if hamburgerButton.waitForExistence(timeout: 10) {
            hamburgerButton.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "01b-HamburgerMenu")

            let closeButton = app.buttons["Close"]
            if closeButton.waitForExistence(timeout: 5) {
                closeButton.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // The in-page segmented toggle — guests can freely switch to My
        // Stream, which should show an inline "log in" prompt rather than
        // being a full-screen gate (Main Stream stays reachable). Scoped to
        // .segmentedControls specifically: the segment's "My Stream" label
        // is identical text to the tab bar's own "My Stream" tab item, so a
        // plain app.buttons["My Stream"] lookup would be ambiguous.
        let myStreamSegment = app.segmentedControls.buttons["My Stream"]
        if myStreamSegment.waitForExistence(timeout: 10) {
            reliableTap(myStreamSegment)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "01d-MyStreamSegment-Guest")

            let mainStreamSegment = app.segmentedControls.buttons["Main Stream"]
            if mainStreamSegment.waitForExistence(timeout: 5) {
                reliableTap(mainStreamSegment)
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // Add Stream tab should never navigate to its own screen — tapping it
        // should snap back and present a sheet (a login prompt, since we're
        // still a guest at this point).
        let addStreamTab = app.buttons["Add Stream"]
        if addStreamTab.waitForExistence(timeout: 10) {
            addStreamTab.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "01c-AddStreamTap-Guest")
            XCTAssertTrue(streamTab.isSelected, "Add Stream must snap back to the previous tab, never become the active tab")

            let addStreamCancel = app.buttons["Cancel"]
            if addStreamCancel.waitForExistence(timeout: 5) {
                addStreamCancel.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        let logInButton = app.navigationBars.buttons["Log In"]
        guard logInButton.waitForExistence(timeout: 10) else {
            XCTFail("Guests should see a Log In entry point on the Main Stream segment")
            return
        }
        logInButton.tap()

        attach(app, name: "02-AfterLogInTap")

        let demoButton = app.buttons["Continue with Demo Data"]
        guard demoButton.waitForExistence(timeout: 20) else {
            XCTFail("Demo login button should exist in Debug builds")
            return
        }
        demoButton.tap()

        // Diagnostic: whatever is on screen immediately after the tap, before any wait.
        attach(app, name: "03-AfterDemoTap")

        // The login sheet should auto-dismiss back to Main Stream once authenticated.
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "04-MainStream-LoggedIn")

        // My Stream segment now shows the authed shows list instead of the
        // inline auth prompt.
        if myStreamSegment.waitForExistence(timeout: 10) {
            reliableTap(myStreamSegment)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "05-MyStream-LoggedIn")

            // Asserted, not an `if` — this is the check that was missing.
            //
            // Show creation disappeared for anyone with exactly one show
            // (reported 2026-10-26) and this suite stayed green throughout,
            // because the lookup sat inside `if waitForExistence` and a
            // vanished control simply skipped the block. A route to creating a
            // show is a requirement, so its absence has to be a failure.
            //
            // Note this guards the My Stream toolbar's "+" only. The wizard's
            // own "Add New Show" row — the control that actually went missing —
            // is unreachable in CI: demo mode's token isn't real, so
            // AddStreamCoordinator.start() fails and the picker never renders
            // (see the wizard block below). Covering that one needs a test
            // signed in with a real token.
            let newShowButton = app.navigationBars.buttons["New Show"]
            XCTAssertTrue(
                newShowButton.waitForExistence(timeout: 10),
                "My Stream must always offer a way to create a show when signed in"
            )
            if newShowButton.exists {
                newShowButton.tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "05b-CreateShow")

                let cancelButton = app.buttons["Cancel"]
                if cancelButton.waitForExistence(timeout: 5) {
                    cancelButton.tap()
                    Thread.sleep(forTimeInterval: 1)
                }
            }

            // Switch back to Main Stream before opening the wizard below —
            // otherwise a show name (e.g. "The Alex Rivera Show") is visible
            // twice at once: once in this tab's own list, still present in
            // the accessibility tree behind the wizard's sheet, and again in
            // the wizard's own show picker, making later lookups ambiguous.
            let mainStreamSegmentAfterLogin = app.segmentedControls.buttons["Main Stream"]
            if mainStreamSegmentAfterLogin.waitForExistence(timeout: 5) {
                reliableTap(mainStreamSegmentAfterLogin)
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // Add Stream wizard, now authenticated — walk through the show
        // picker (demo data has 2 shows) and the type/format step. Stop
        // before anything requiring real camera access or a real upload.
        if addStreamTab.waitForExistence(timeout: 10) {
            addStreamTab.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "06-AddStreamWizard-ShowStep")

            // The wizard legitimately cannot load its show picker here.
            // Demo mode signs in with a fake `demo-token`, and
            // AddStreamCoordinator.start() deliberately has no mock fallback
            // (fake show ids used to sail into a real create-stage call that
            // the backend rejected), so the step renders its load-failure
            // state with a Try Again button instead.
            //
            // This block used to tap `firstShowRow` unconditionally after a
            // bare `waitForExistence`, which passed on the *stale* copy of the
            // label still in the accessibility tree behind the sheet and then
            // failed the tap as "not hittable" — one of the three failures
            // this suite carried from 12 Oct. Assert that the wizard presented
            // one of its two valid states, and only walk the picker when the
            // row is genuinely tappable.
            let firstShowRow = app.staticTexts["The Alex Rivera Show"].firstMatch
            let pickerLoadFailed = app.buttons["Try Again"]
            XCTAssertTrue(
                firstShowRow.waitForExistence(timeout: 10) || pickerLoadFailed.exists,
                "Add Stream wizard showed neither a show picker nor its retry state"
            )
            if firstShowRow.exists && firstShowRow.isHittable {
                firstShowRow.tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "06b-AddStreamWizard-TypeFormat")

                let nextButton = app.buttons["Next"]
                if nextButton.waitForExistence(timeout: 5) {
                    nextButton.tap()
                    Thread.sleep(forTimeInterval: 1)
                    attach(app, name: "06c-AddStreamWizard-EpisodeDetails")
                }
            }

            let wizardCancel = app.buttons["Cancel"]
            if wizardCancel.waitForExistence(timeout: 5) {
                wizardCancel.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        let accountTab = app.buttons["My Account"]
        if accountTab.waitForExistence(timeout: 10) {
            accountTab.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "07-MyAccount")

            // Settings and its Billing/Account sub-screens (Subscription,
            // Payment, Change Password, Delete Account) — all new this pass,
            // none previously covered by this test. Each step is optional
            // (waitForExistence, no XCTFail) so a missing row never aborts
            // the rest of the run, matching the rest of this file.
            // These rows used to sit behind a gear button in the toolbar. As of
            // 2026-10-09 My Account IS the full account hub (the gear and the
            // separate Settings screen are gone), so they're reached directly
            // and there's no intermediate hop to screenshot.
            //
            // Each step stays optional (waitForExistence, no XCTFail) so a
            // missing row never aborts the rest of the run, matching the rest
            // of this file.
            do {
                attach(app, name: "08-MyAccount-Full")

                let subscriptionRow = app.buttons["Subscription"]
                if subscriptionRow.waitForExistence(timeout: 10) {
                    subscriptionRow.tap()
                    Thread.sleep(forTimeInterval: 2)
                    attach(app, name: "09-Subscription")
                    goBack(app)
                }

                let paymentRow = app.buttons["Payment"]
                if paymentRow.waitForExistence(timeout: 10) {
                    paymentRow.tap()
                    Thread.sleep(forTimeInterval: 2)
                    attach(app, name: "10-Payment")
                    goBack(app)
                }

                let changePasswordRow = app.buttons["Change Password"]
                if changePasswordRow.waitForExistence(timeout: 10) {
                    changePasswordRow.tap()
                    Thread.sleep(forTimeInterval: 1)
                    attach(app, name: "11-ChangePassword")
                    goBack(app)
                }

                let deleteAccountRow = app.buttons["Delete Account"]
                if deleteAccountRow.waitForExistence(timeout: 10) {
                    deleteAccountRow.tap()
                    Thread.sleep(forTimeInterval: 1)
                    attach(app, name: "12-DeleteAccount")
                    goBack(app)
                }
            }
        }
    }

    /// Asserts every bottom-bar destination actually renders something.
    ///
    /// This is the test that was missing when My Account shipped blank in build
    /// 4 (reported 2026-10-09). Nothing in the suite checked that a tab's
    /// content existed, so dropping `.tabItem` from the TabView's children —
    /// which makes them render empty — compiled, passed CI, and reached
    /// TestFlight. `testCaptureKeyScreens` tapped My Account and screenshotted
    /// it, but a screenshot of an empty screen is still a screenshot: nothing
    /// failed.
    ///
    /// Deliberately asserts on content INSIDE each tab rather than on the tab
    /// button, because the buttons kept working the whole time the screens
    /// behind them were blank.
    func testEveryTabRendersContent() throws {
        let app = launchApp()

        let hubTab = app.buttons["Hub"]
        guard hubTab.waitForExistence(timeout: 20) else {
            XCTFail("Custom bottom bar should exist on launch")
            return
        }

        // Hub, as a guest: the Main Stream / My Stream toggle is its content.
        XCTAssertTrue(
            app.segmentedControls.buttons["Main Stream"].waitForExistence(timeout: 10),
            "Hub tab rendered no content"
        )

        // Sign in, so My Account shows the real hub rather than its auth gate.
        let logInButton = app.navigationBars.buttons["Log In"]
        if logInButton.waitForExistence(timeout: 10) {
            logInButton.tap()
            let demoButton = app.buttons["Continue with Demo Data"]
            if demoButton.waitForExistence(timeout: 20) {
                demoButton.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        app.buttons["My Account"].tap()
        Thread.sleep(forTimeInterval: 1)

        // Destinations and the screenshot come first, while the hub is still
        // scrolled to the top — both describe the top of the screen, and the
        // scroll below would invalidate them.
        XCTAssertTrue(
            app.buttons["Destinations"].waitForExistence(timeout: 10),
            "My Account rendered no content, or should lead with Destinations per the wireframe"
        )
        attach(app, name: "99-TabContent-MyAccount")

        // Log Out is the last row on the account hub, so reaching it proves the
        // screen rendered all the way down AND that the floating bar isn't
        // covering the bottom of it — the second half of the 2026-10-09 report.
        //
        // It has to be scrolled to first. SwiftUI's List is lazy: rows below
        // the fold are absent from the accessibility tree entirely, so the
        // previous bare `waitForExistence` reported a perfectly healthy screen
        // as "rendered no content" and the follow-up tap then found no match —
        // two of the three failures this suite carried from 12 Oct.
        //
        // `isHittable`, not just `exists`, is what preserves the original
        // intent: a Log Out button sitting underneath the floating tab bar
        // exists but cannot be tapped, and that is the bug being guarded.
        let logOut = app.buttons["Log Out"]
        XCTAssertTrue(
            scrollUntilHittable(app, logOut),
            "My Account rendered no content, or its last row is unreachable"
        )

        // Logging out must land back on Hub, not sit on the account tab showing
        // a login prompt (reported 2026-10-11).
        logOut.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(
            app.segmentedControls.buttons["Main Stream"].waitForExistence(timeout: 10),
            "Logging out should return to the Hub landing page"
        )
        attach(app, name: "99-AfterLogout-Landing")
    }

    /// Launches with deterministic public content.
    ///
    /// Without `-StreamrUseMockDiscovery` the Main Stream carousels show
    /// whatever is live on production, so the captured screenshots change from
    /// run to run and can pick up other people's test uploads — see
    /// MockData.useMockDiscovery. Screenshots that go on an App Store listing
    /// have to be reproducible.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-StreamrUseMockDiscovery"]
        app.launch()
        return app
    }

    /// Swipes up until `element` is actually tappable, or gives up.
    ///
    /// Needed because SwiftUI's List only builds the rows near the viewport:
    /// a row below the fold is not merely off-screen, it is absent from the
    /// accessibility tree, so `waitForExistence` on it fails outright.
    private func scrollUntilHittable(
        _ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 6
    ) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element.exists && element.isHittable
    }

    private func goBack(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Plain `.tap()` triggers XCTest's automatic "scroll to visible" pass —
    /// harmless normally, but the segmented Main Stream/My Stream toggle now
    /// lives in its own row under the nav bar (moved out of .principal to
    /// make room for the centered logo), and in that position the scroll
    /// action reliably fails with kAXErrorCannotComplete even though the
    /// button is already fully on-screen. A direct coordinate tap skips that
    /// scroll attempt entirely.
    private func reliableTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
