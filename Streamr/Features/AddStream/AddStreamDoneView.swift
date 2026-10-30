import SwiftUI

struct AddStreamDoneView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(StreamrColor.primary)
            Text("You're all set!")
                .font(StreamrFont.title(22))
                .foregroundStyle(.white)
            PrimaryButton(title: "Done", action: onDone)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
