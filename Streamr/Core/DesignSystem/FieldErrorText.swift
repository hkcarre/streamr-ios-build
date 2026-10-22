import SwiftUI

/// Inline field-level error message, shown directly under the field it
/// belongs to instead of only dimming the submit button with no explanation.
struct FieldErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(StreamrFont.caption(12))
                .foregroundStyle(StreamrColor.liveRed)
                .transition(.opacity)
        }
    }
}
