import SwiftUI

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
            Text("or continue with")
                .font(StreamrFont.caption())
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
        }
    }
}
