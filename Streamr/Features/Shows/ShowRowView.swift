import SwiftUI

struct ShowRowView: View {
    let show: Show

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(StreamrColor.surfaceDark)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(StreamrFont.headline(15))
                    .foregroundStyle(.white)
                if let description = show.description, !description.isEmpty {
                    Text(description)
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }

            Spacer()

            if show.autoSharing == true {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(StreamrColor.primary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
