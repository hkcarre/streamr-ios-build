import SwiftUI

/// Shared styled input used across the auth screens, matching the app's
/// dark-gradient / glass-panel look.
struct StreamrTextField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    /// Left nil, this derives from the field itself: never for secure fields
    /// and email addresses, sentence case for everything else. Deriving it
    /// rather than defaulting to one value means no existing call site has to
    /// change and none can be forgotten.
    var autocapitalization: TextInputAutocapitalization?

    @State private var isRevealed = false

    private var effectiveCapitalization: TextInputAutocapitalization {
        if let autocapitalization { return autocapitalization }
        if isSecure || keyboardType == .emailAddress { return .never }
        return .sentences
    }

    var body: some View {
        Group {
            if isSecure && !isRevealed {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .textContentType(textContentType)
        .keyboardType(keyboardType)
        .autocorrectionDisabled()
        // Was hardcoded `.never` on the shared field, so EVERY use got it —
        // First name, Last name, Show name, Episode Name, Description and Tags
        // all typed in lowercase with no way to opt out. `.never` is right for
        // email and password, which is what it was added for; everything else
        // wants normal sentence casing.
        .textInputAutocapitalization(effectiveCapitalization)
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.leading, 16)
        // Reserves room for the reveal button so a long password doesn't run
        // underneath it.
        .padding(.trailing, isSecure ? 52 : 16)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .trailing) {
            if isSecure {
                // 44x44 and labelled, and the field reserves room for it below
                // — the glyph used to sit on top of the text, so a long
                // password ran underneath it.
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                .padding(.trailing, 4)
            }
        }
    }
}
