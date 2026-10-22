import SwiftUI

/// One screen: Stream/Record/Upload choice + Video/Audio toggle + Next —
/// confirmed by the newest wireframe revision to be a single step, not
/// three separate screens. All three type options are always tappable —
/// deliberately not replicating the website's subscription-tier gating
/// (checkStreamPermission), out of scope for this pass.
struct AddStreamTypeFormatStepView: View {
    @ObservedObject var coordinator: AddStreamCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(VideoType.allCases) { type in
                        typeRow(type)
                    }
                }

                Picker("Format", selection: $coordinator.format) {
                    ForEach(StreamFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                PrimaryButton(title: "Next") {
                    coordinator.confirmTypeAndFormat()
                }
            }
            .padding(24)
        }
    }

    /// Liquid glass with the violet outline, matching the bottom navigator and
    /// the reference button supplied 2026-10-11 — see `LiquidGlass`.
    ///
    /// Selection is carried by the WEIGHT of that outline (1pt dimmed vs 2pt at
    /// full strength) and a slightly brighter fill, not by a different colour.
    /// The previous version switched to the green brand accent when selected,
    /// which would have put a second accent colour on a surface that is now
    /// defined by its violet edge. Keeping one colour and varying its emphasis
    /// leaves the selected row obvious without the row changing identity, and
    /// the checkmark remains the unambiguous non-colour cue.
    private func typeRow(_ type: VideoType) -> some View {
        let isSelected = coordinator.type == type
        return Button {
            coordinator.type = type
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon(for: type))
                Text(type.displayName)
                    .font(StreamrFont.headline(16))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tintOpacity: isSelected ? 0.18 : 0.08,
                outlineOpacity: isSelected ? 1 : 0.45,
                lineWidth: isSelected ? 2 : 1,
                shadowRadius: isSelected ? 10 : 6,
                shadowOpacity: isSelected ? 0.22 : 0.12
            )
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func icon(for type: VideoType) -> String {
        switch type {
        case .stream: "dot.radiowaves.left.and.right"
        case .record: "record.circle"
        case .upload: "square.and.arrow.up"
        }
    }
}
