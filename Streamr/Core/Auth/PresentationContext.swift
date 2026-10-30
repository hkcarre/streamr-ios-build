import UIKit

/// Small shared helper so the Google/Facebook/Apple sign-in wrappers don't
/// each duplicate the same UIKit scene-traversal logic to find something to
/// present their SDK's UI from.
enum PresentationContext {
    @MainActor
    static func topMostViewController() -> UIViewController? {
        guard let root = keyWindow()?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    @MainActor
    static func keyWindow() -> UIWindow? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?
            .windows.first { $0.isKeyWindow }
    }
}
