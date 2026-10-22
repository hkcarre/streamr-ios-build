import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(StreamrFont.headline(17))
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(StreamrColor.primary)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isLoading)
    }
}
