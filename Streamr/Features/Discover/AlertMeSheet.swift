import SwiftUI

/// The wireframe's "Choose the updates you want to receive" tray. Each row
/// toggles immediately on tap (matches the underlying API — every call is
/// itself a toggle, there's no separate staged "Save" step) rather than
/// staging a selection first, which better matches how the app's other
/// immediate-effect toggles already behave (e.g. CreateEditShowView's
/// auto-share).
struct AlertMeSheet: View {
    @ObservedObject var viewModel: AlertMeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Notify me about:")
                    .font(StreamrFont.headline(16))
                    .foregroundStyle(.white)

                optionRow(type: .show, title: "This show", subtitle: "New streams from this show only")
                optionRow(type: .creator, title: "This creator", subtitle: "Every new stream from this creator")

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                Spacer()
            }
            .padding(24)
            .streamrBackground()
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func optionRow(type: AlertType, title: String, subtitle: String) -> some View {
        let isSelected = viewModel.activeType == type

        return Button {
            Task { await viewModel.toggle(type) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? StreamrColor.primary : .white.opacity(0.4))
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StreamrFont.body(15))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(viewModel.isLoading)
    }
}
