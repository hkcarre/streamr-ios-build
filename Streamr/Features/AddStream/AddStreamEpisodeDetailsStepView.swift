import SwiftUI

/// Season/Episode as fixed 1-50 dropdowns and Tags as free comma-separated
/// text with no extra limits — both confirmed acceptable v1 scope directly
/// by the wireframe's author. Chat visibility only renders for type == .stream
/// (confirmed: Record/Upload never send that field at all).
struct AddStreamEpisodeDetailsStepView: View {
    @ObservedObject var coordinator: AddStreamCoordinator

    private static let seasonEpisodeRange = Array(1...50).map(String.init)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StreamrTextField(title: "Episode Name", text: $coordinator.title)
                StreamrTextField(title: "Description", text: $coordinator.episodeDescription)

                if coordinator.type != .upload {
                    Toggle(isOn: $coordinator.guest) {
                        Text("Invite Guest")
                            .font(StreamrFont.body(14))
                            .foregroundStyle(.white)
                    }
                    .tint(StreamrColor.primary)
                }

                HStack(spacing: 14) {
                    dropdown(title: "Season", selection: $coordinator.season)
                    dropdown(title: "Episode", selection: $coordinator.episode)
                }

                categoryPicker

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.6))
                    StreamrTextField(title: "Comma-separated", text: $coordinator.tagsText)
                }

                DatePicker("Scheduled Time", selection: $coordinator.scheduledTime)
                    .datePickerStyle(.compact)
                    .foregroundStyle(.white)
                    .tint(StreamrColor.primary)

                if coordinator.type == .stream {
                    // Labeled "Chat"/on-off, not "Public/Private" — confirmed
                    // 2026-09-02 that reads as ambiguous with show/episode
                    // visibility, which this control has nothing to do with
                    // (it only ever maps to the stream's chat field; already
                    // correctly hidden for Record/Upload below, which have no
                    // live chat at all). SwiftUI's segmented picker style
                    // never renders the Picker's own title, hence the
                    // separate caption Text above it, matching every other
                    // field on this screen.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chat")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.6))
                        Picker("Chat", selection: $coordinator.chatVisibility) {
                            Text("Chat On").tag(ChatVisibility.publicChat)
                            Text("Chat Off").tag(ChatVisibility.privateChat)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let wizardError = coordinator.wizardError {
                    Text(wizardError)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                PrimaryButton(
                    title: coordinator.type == .upload ? "Next" : "Enter Staging Area",
                    isLoading: coordinator.isCreatingStage
                ) {
                    coordinator.submitEpisodeDetails()
                }
            }
            .padding(24)
        }
        .task { await coordinator.loadCategoriesIfNeeded() }
    }

    private func dropdown(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(StreamrFont.caption())
                .foregroundStyle(.white.opacity(0.6))
            Menu {
                ForEach(Self.seasonEpisodeRange, id: \.self) { value in
                    Button(value) { selection.wrappedValue = value }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(StreamrFont.caption())
                .foregroundStyle(.white.opacity(0.6))
            Menu {
                ForEach(coordinator.categories) { category in
                    Button(category.name) {
                        coordinator.selectedCategoryId = category.id
                    }
                }
            } label: {
                HStack {
                    Text(coordinator.categories.first { $0.id == coordinator.selectedCategoryId }?.name ?? "Select a category")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
