import SwiftUI
import FBSDKCoreKit

/// Required by Facebook's SDK — confirmed against developers.facebook.com's
/// current iOS setup guide 2026-10-06, found missing entirely during a
/// security/correctness audit. Without this, FBSDKCoreKit's
/// `ApplicationDelegate.shared` never initializes from the App ID/Client
/// Token in Info.plist at all, so `LoginManager().logIn(...)`
/// (FacebookAuthService.swift) was running against an uninitialized SDK —
/// not just missing the redirect callback below, the SDK itself was never
/// set up. `@UIApplicationDelegateAdaptor` is Apple's own supported bridge
/// for wiring a UIKit-only SDK requirement into a pure SwiftUI app
/// lifecycle (no UIKit AppDelegate existed anywhere in this app before).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        return true
    }
}

@main
struct StreamrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    /// Block list, read by every screen that renders someone else's content.
    /// App-level so a block made in the player is honoured by the chat panel
    /// and the discover lists without anything being passed between them.
    @StateObject private var moderation = ModerationStore()
    /// Crash and hang reports. Constructed here, at launch, because MetricKit
    /// hands over everything it has been holding as soon as it has a
    /// subscriber — a store created later, when some screen first asks for it,
    /// would miss the delivery describing the crash that just happened.
    @StateObject private var diagnostics = DiagnosticsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(moderation)
                .environmentObject(diagnostics)
                .preferredColorScheme(.dark)
                // The other half of the same gap — without forwarding the
                // OAuth redirect URL back into the SDK, Facebook Login would
                // open the login flow but never complete it: the app had no
                // way to receive the callback once FBSDKCoreKit itself
                // redirects back via the fb<appid>:// scheme (already
                // declared in project.yml's CFBundleURLTypes, just never
                // consumed by anything). Google needs no equivalent call —
                // its modern signIn(withPresenting:) API completes the OAuth
                // round-trip internally via ASWebAuthenticationSession,
                // confirmed against Google's own SDK docs/README the same
                // audit pass that found this Facebook gap.
                .onOpenURL { url in
                    ApplicationDelegate.shared.application(
                        UIApplication.shared,
                        open: url,
                        sourceApplication: nil,
                        annotation: UIApplication.OpenURLOptionsKey.annotation
                    )
                }
        }
    }
}
