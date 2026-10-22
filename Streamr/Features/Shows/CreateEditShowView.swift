import SwiftUI
import PhotosUI

struct CreateEditShowView: View {
    @StateObject private var viewModel: CreateEditShowViewModel
    @Environment(\.dismiss) private var dismiss
    let onSave: (Show) -> Void
    @State private var showingCopiedConfirmation = false

    init(mode: CreateEditShowViewModel.Mode, onSave: @escaping (Show) -> Void) {
        _viewModel = StateObject(wrappedValue: CreateEditShowViewModel(mode: mode))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                        coverPicker
                    }
                    FieldErrorText(message: viewModel.artworkError)

                    VStack(alignment: .leading, spacing: 6) {
                        StreamrTextField(title: "Show name", text: $viewModel.name)
                            .onChange(of: viewModel.name) { _, _ in viewModel.clearNameError() }
                        FieldErrorText(message: viewModel.nameError)
                    }
                    StreamrTextField(title: "Description", text: $viewModel.description)

                    categoryPicker
                    FieldErrorText(message: viewModel.categoryError)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $viewModel.autoSharing) {
                            Text("Automatic Sharing")
                                .font(StreamrFont.body(14))
                                .foregroundStyle(.white)
                        }
                        .tint(StreamrColor.primary)
                        .onChange(of: viewModel.autoSharing) { _, isOn in
                            Task { await viewModel.autoSharingToggled(isOn) }
                        }

                        Text("Checking this sets newly processed streams to publish to connected external accounts.")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if case .edit = viewModel.mode {
                        platformSelectionPanel
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.liveRed)
                    }

                    PrimaryButton(title: viewModel.saveButtonTitle, isLoading: viewModel.isSaving) {
                        Task {
                            if let show = await viewModel.save() {
                                onSave(show)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(24)
            }
            .streamrBackground()
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await viewModel.loadCategories()
                if case .edit = viewModel.mode {
                    await viewModel.loadConnectedAccountsIfNeeded()
                }
            }
            .sheet(isPresented: $viewModel.showingConnectPrompt, onDismiss: {
                Task { await viewModel.loadConnectedAccountsIfNeeded(force: true) }
            }) {
                // DestinationsView is pure content, no nav chrome of its own
                // (matches this app's established "parent owns nav chrome"
                // convention — see DiscoverView's doc comment) — fine when
                // pushed via NavigationLink from SettingsView (its other call
                // site), which supplies a back button automatically, but a
                // real dead end here: presented as a sheet with no
                // NavigationStack and no dismiss button at all, confirmed
                // live 2026-09-02 as a trap the only way out of was force-
                // quitting the app.
                NavigationStack {
                    DestinationsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { viewModel.showingConnectPrompt = false }
                            }
                        }
                }
            }
        }
    }

    /// Mirrors AllShowsList.tsx's "Select Platforms" panel — per-show
    /// provider selection, distinct from the Automatic Sharing master
    /// toggle above. Only connected providers get a row (website does the
    /// same: `renderPlatform` is a no-op unless `isConnected`). Facebook
    /// deliberately excluded — see ShowPayload.selectedProviders' doc
    /// comment for why.
    private var platformSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Select Platforms")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button("Manage Connections") {
                    viewModel.showingConnectPrompt = true
                }
                .font(StreamrFont.caption(12))
                .foregroundStyle(StreamrColor.primary)
            }

            VStack(spacing: 0) {
                ForEach(DestinationProvider.allCases.filter { $0 != .facebook && viewModel.isProviderConnected($0) }) { provider in
                    platformRow(
                        icon: Image(provider.iconAssetName).resizable().aspectRatio(contentMode: .fit),
                        title: provider.displayName,
                        isOn: viewModel.selectedProviders.contains(provider.rawValue)
                    ) {
                        viewModel.toggleProvider(provider.rawValue)
                    }
                }

                platformRow(
                    icon: Image(systemName: "dot.radiowaves.left.and.right").resizable().aspectRatio(contentMode: .fit),
                    title: "Generate / Update RSS",
                    subtitle: "Use this to connect Apple Podcasts, Spotify, iHeartPodcasts or other RSS distributors.",
                    isOn: viewModel.selectedProviders.contains("RSS")
                ) {
                    viewModel.toggleProvider("RSS")
                }

                HStack {
                    Spacer()
                    Button(showingCopiedConfirmation ? "Copied!" : "Copy RSS URL") {
                        if viewModel.copyRSSLink() {
                            showingCopiedConfirmation = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showingCopiedConfirmation = false
                            }
                        }
                    }
                    .font(StreamrFont.caption(12))
                    .foregroundStyle((viewModel.rssLink?.isEmpty ?? true) ? .white.opacity(0.3) : StreamrColor.primary)
                    .disabled(viewModel.rssLink?.isEmpty ?? true)
                }
                .padding(.top, 4)
            }
        }
    }

    private func platformRow(
        icon: some View, title: String, subtitle: String? = nil, isOn: Bool, toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                icon
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StreamrFont.body(14))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(StreamrFont.caption(11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? StreamrColor.primary : .white.opacity(0.4))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var coverPicker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            if let coverImage = viewModel.coverImage {
                coverImage
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28))
                    Text("Add cover image")
                        .font(StreamrFont.caption())
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(StreamrFont.caption())
                .foregroundStyle(.white.opacity(0.6))

            if viewModel.isLoadingCategories && viewModel.categories.isEmpty {
                ProgressView().tint(.white)
            } else {
                Menu {
                    ForEach(viewModel.categories) { category in
                        Button(category.name) {
                            viewModel.selectedCategoryId = category.id
                            viewModel.clearCategoryError()
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedCategoryName)
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

    private var selectedCategoryName: String {
        viewModel.categories.first(where: { $0.id == viewModel.selectedCategoryId })?.name ?? "Select a category"
    }
}
