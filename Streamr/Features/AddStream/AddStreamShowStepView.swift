import SwiftUI

/// Step 1 of the wizard: pick the show this episode belongs to, or make a new
/// one. Zero shows gives the empty-state prompt; any other count gives the
/// list plus "Add New Show".
///
/// This is the wireframe's Show Name dropdown (092726), which always offers
/// "+Add New Show" alongside the existing shows — kept as a list rather than a
/// literal dropdown so each row can carry its artwork and title, which is what
/// stops an episode attaching to the wrong show.
///
/// Show creation itself reuses CreateEditShowView unmodified as a nested sheet
/// (sheet-on-sheet is already an established pattern here — HamburgerMenuView
/// presents LoginView the same way).
struct AddStreamShowStepView: View {
    @ObservedObject var coordinator: AddStreamCoordinator
    @State private var showingCreateShow = false

    var body: some View {
        Group {
            if let loadError = coordinator.showsLoadError {
                // A failed fetch is NOT an empty account — see
                // AddStreamCoordinator.start().
                failedState(loadError)
            } else if coordinator.myShows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(coordinator.myShows) { show in
                        ShowRowView(show: show)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { coordinator.selectShow(show) }
                    }

                    Button {
                        showingCreateShow = true
                    } label: {
                        // Named as the wireframe names it, so the control a
                        // creator is told to look for is the one on screen.
                        Label("Add New Show", systemImage: "plus")
                            .font(StreamrFont.body(15))
                            .foregroundStyle(StreamrColor.primary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $showingCreateShow) {
            CreateEditShowView(mode: .create) { show in
                coordinator.showCreated(show)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(StreamrColor.warningGold)
            Text(message)
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            PrimaryButton(title: "Try Again") {
                Task { await coordinator.start() }
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text("You haven't created a show yet.")
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            PrimaryButton(title: "Create a Show") {
                showingCreateShow = true
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
