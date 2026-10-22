import SwiftUI

/// Pure content — no NavigationStack/toolbar/background of its own. Embedded
/// by `StreamHomeView` as the "My Stream" segment; `showingCreateSheet` is
/// driven by that parent's toolbar "+ New Show" button rather than local
/// state, so one control triggers the same sheet this view already owned.
///
/// Backed by POST /show/list, with create/edit/delete wired to
/// /show/create, /show/update, /show/delete/:id.
struct MyShowsView: View {
    @StateObject private var viewModel = MyShowsViewModel()
    @Binding var showingCreateSheet: Bool
    @State private var editingShow: Show?
    @State private var deletingShow: Show?

    var body: some View {
        Group {
            if viewModel.shows.isEmpty && viewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.shows.isEmpty {
                emptyState
            } else {
                List {
                    if let errorMessage = viewModel.errorMessage {
                        // Outside the empty state on purpose: deleting a show
                        // always happens with a non-empty list, so a failure
                        // rendered only in `emptyState` could never be seen —
                        // the swipe simply appeared to do nothing.
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.warningGold)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(viewModel.shows) { show in
                        // Opens the SHOW, not an edit form. Tapping your own
                        // show used to go straight to CreateEditShowView, which
                        // meant a creator had no route to their own episode
                        // list at all — the only way to see their own episodes
                        // was to find the show in the public Main Stream list.
                        // Editing moves to the swipe actions beside Delete.
                        NavigationLink(value: ShowRoute(show: show)) {
                            ShowRowView(show: show)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            // Confirmed, unlike before: a show contains every
                            // episode under it, and a stray swipe destroyed the
                            // lot with no undo. Episodes, cards, the account
                            // and the subscription all confirm already.
                            Button(role: .destructive) {
                                deletingShow = show
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingShow = show
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(StreamrColor.accentBlue)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingCreateSheet) {
            CreateEditShowView(mode: .create) { show in
                viewModel.upsert(show)
            }
        }
        .sheet(item: $editingShow) { show in
            CreateEditShowView(mode: .edit(show)) { updated in
                viewModel.upsert(updated)
            }
        }
        .alert(
            "Delete \(deletingShow?.name ?? "this show")?",
            isPresented: Binding(
                get: { deletingShow != nil },
                set: { if !$0 { deletingShow = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletingShow = nil }
            Button("Delete", role: .destructive) {
                if let show = deletingShow {
                    Task { await viewModel.delete(show) }
                }
                deletingShow = nil
            }
        } message: {
            Text("This deletes the show and every episode in it. It can't be undone.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(viewModel.errorMessage ?? "You haven't created a show yet.")
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
