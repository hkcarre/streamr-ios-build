import SwiftUI

/// Account-level connect/disconnect for auto-share destinations — mirrors
/// orca-nebula's SocialMedia.tsx. Not gated behind being live: connect once
/// here, then show/stream creation just checks off what's already connected.
struct DestinationsView: View {
    @StateObject private var viewModel = DestinationsViewModel()

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(StreamrFont.caption())
                    .foregroundStyle(StreamrColor.liveRed)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let successMessage = viewModel.successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.green)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(DestinationProvider.allCases) { provider in
                    providerRow(provider)
                }
            } header: {
                // "auto-share" dropped 2026-10-11 at its author's request
                // ("edit destinations instruction, remove 'auto'") — sharing is
                // something the creator sets up and the platform then does, and
                // "auto" oversold it as hands-off.
                Text("Connect a platform to share new streams there")
                    .textCase(nil)
            }

            Section {
                ForEach(DestinationBadge.allCases) { badge in
                    badgeRow(badge)
                }
            } header: {
                Text("Available once your first stream has ended")
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .streamrBackground()
        .navigationTitle("Destinations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $viewModel.connectURL, onDismiss: {
            viewModel.stopWatchingForConnection()
            Task { await viewModel.load() }
        }) { identifiableURL in
            SafariView(url: identifiableURL.url)
        }
    }

    private func providerRow(_ provider: DestinationProvider) -> some View {
        let isConnected = viewModel.isConnected(provider)
        let isBusy = viewModel.busyProvider == provider
        let isDisabled = viewModel.busyProvider != nil

        return HStack(spacing: 14) {
            Image(provider.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            Text(provider.displayName)
                .font(StreamrFont.body(16))
                .foregroundStyle(.white)

            Spacer()

            Button {
                Task {
                    if isConnected {
                        await viewModel.disconnect(provider)
                    } else {
                        await viewModel.connect(provider)
                    }
                }
            } label: {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(isConnected ? "Disconnect" : "Connect")
                        .font(StreamrFont.caption())
                        .foregroundStyle(isConnected ? StreamrColor.liveRed : .black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isConnected ? Color.white.opacity(0.12) : StreamrColor.primary)
                        .clipShape(Capsule())
                }
            }
            .disabled(isDisabled)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func badgeRow(_ badge: DestinationBadge) -> some View {
        HStack(spacing: 14) {
            Image(badge.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .opacity(0.6)

            Text(badge.displayName)
                .font(StreamrFont.body(16))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}
