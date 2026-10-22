import SwiftUI

/// The wireframe's "Edit Episode Details" screen. Only title/description/
/// season/episode/tags are editable — matches the real backend form
/// exactly (StreamModel.tsx); no artwork (show-level only), type, format,
/// or category field exists in the real edit flow either. "Replace Episode
/// Audio"/RSS replacement from the same wireframe is deliberately deferred
/// — a materially bigger feature (S3 upload + RSS regen) than this pass's
/// scope, not silently dropped.
struct EditEpisodeView: View {
    let episode: StreamItem
    @ObservedObject var viewModel: ShowDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var season: String
    @State private var episodeNumber: String
    @State private var tagsText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let seasonEpisodeRange = Array(1...50).map(String.init)

    init(episode: StreamItem, viewModel: ShowDetailViewModel) {
        self.episode = episode
        self.viewModel = viewModel
        _title = State(initialValue: episode.title)
        _description = State(initialValue: episode.description ?? "")
        _season = State(initialValue: episode.season.map(String.init) ?? "1")
        _episodeNumber = State(initialValue: episode.episode.map(String.init) ?? "1")
        _tagsText = State(initialValue: (episode.tags ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StreamrTextField(title: "Episode Name", text: $title)
                    StreamrTextField(title: "Description", text: $description)

                    HStack(spacing: 14) {
                        dropdown(title: "Season", selection: $season)
                        dropdown(title: "Episode", selection: $episodeNumber)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.6))
                        StreamrTextField(title: "Comma-separated", text: $tagsText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.liveRed)
                    }

                    PrimaryButton(title: "Save", isLoading: isSaving) {
                        Task { await save() }
                    }
                }
                .padding(24)
            }
            .streamrBackground()
            .navigationTitle("Edit Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
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

    private var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }
    }

    private func save() async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Give this episode a name."
            return
        }
        // Matches StreamModel.tsx's Yup schema exactly (2-200 chars) — a
        // different, stricter range than Show's own description field.
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDescription.count >= 2 && trimmedDescription.count <= 200 else {
            errorMessage = "Description must be between 2 and 200 characters."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let success = await viewModel.update(
            episodeId: episode.id, title: title, description: description,
            season: season, episode: episodeNumber, tags: tags
        )

        if success {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage
        }
    }
}
