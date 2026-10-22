import Foundation

/// Wraps a connect URL so it can drive `.sheet(item:)` — `URL` itself isn't
/// `Identifiable`.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
final class DestinationsViewModel: ObservableObject {
    @Published private(set) var accounts: [ConnectedAccount] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var busyProvider: DestinationProvider?
    @Published var connectURL: IdentifiableURL?
    @Published private(set) var successMessage: String?

    private var connectionWatchTask: Task<Void, Never>?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.request(
                API.Destinations.connectedAccounts,
                as: APIResponse<[ConnectedAccount]>.self
            )
            accounts = response.data ?? []
        } catch {
            // A cancelled pull-to-refresh isn't a failure — see
            // Error.isCancellation. Returning early also keeps the real
            // connected accounts on screen instead of replacing them with
            // demo data in DEBUG.
            guard !error.isCancellation else { return }
            #if DEBUG
            accounts = MockData.connectedAccounts
            #else
            errorMessage = error.localizedDescription
            #endif
        }
    }

    func isConnected(_ provider: DestinationProvider) -> Bool {
        accounts.first(where: { $0.provider == provider.rawValue })?.isConnected ?? false
    }

    /// Fetches the OAuth kickoff URL and hands it to the view to present via
    /// SFSafariViewController. There's no way to detect completion from inside
    /// that flow (the web app's popup+postMessage approach has no iOS
    /// equivalent, and the custom-scheme redirect path is a follow-up pending
    /// backend confirmation — see Endpoint.swift's API.Destinations doc
    /// comment), so DestinationsView re-`load()`s on dismissal instead,
    /// mirroring the web app's own verifyConnectedQuietly fallback.
    func connect(_ provider: DestinationProvider) async {
        busyProvider = provider
        errorMessage = nil
        defer { busyProvider = nil }

        do {
            // RAW response, NOT wrapped in APIResponse's {data:…} envelope —
            // confirmed live 2026-10-06 against a real authenticated session:
            //   GET /v1/shareStream/connect/youtube
            //   -> {"url":"https://accounts.google.com/o/oauth2/v2/auth?…"}
            //
            // This was decoded as APIResponse<ConnectURLResponse> before, so
            // `response.data` was always nil and every single Connect tap fell
            // into the guard below with "Couldn't start connecting …" — the
            // destinations feature could never work for any provider. The web
            // app reads `data.url` straight off the response body too
            // (orca-nebula src/services/shareStream.ts), which is what gave it
            // away. Same raw-envelope family as generate-video-url,
            // replace-audio-direct, viewer/get-token and show/update.
            //
            // Note /user/connected/accounts IS wrapped ({"data":[],"message":…}),
            // so `load()` above is correct as-is — the inconsistency is
            // per-endpoint, not per-feature.
            let response = try await APIClient.shared.request(
                API.Destinations.connect(provider), as: ConnectURLResponse.self
            )
            connectURL = IdentifiableURL(url: response.url)
            startWatchingForConnection(provider)
        } catch {
            errorMessage = "Couldn't start connecting \(provider.displayName) — \(error.localizedDescription)"
        }
    }

    /// Polls `/user/connected/accounts` while the Safari sheet is open and
    /// closes it the moment the provider reports connected.
    ///
    /// Why this exists: the OAuth redirect lands on the *website's* profile
    /// page inside the sheet, which on a phone renders the desktop site's
    /// "visit on desktop" message — so the host finishes authorising and is
    /// left looking at a confusing web page with no indication it worked, and
    /// has to dismiss it manually (reported 2026-10-07).
    ///
    /// The connection is recorded server-side (the OAuth `state` carries the
    /// user id, and `redirect_uri` points at the backend's own callback), so
    /// the app doesn't need to see the redirect at all — it just needs to
    /// notice the result. Polling turns that into an automatic close plus a
    /// success message, with no backend change and no mobile-specific
    /// confirmation page to build.
    ///
    /// 2s interval, 90s ceiling: long enough to complete a Google consent
    /// screen including a login, short enough that it stops if the host
    /// abandons it. Cancelled on dismissal so a sheet closed by hand doesn't
    /// leave a task running.
    private func startWatchingForConnection(_ provider: DestinationProvider) {
        connectionWatchTask?.cancel()
        connectionWatchTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(90)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }

                // Quiet refresh: a transient failure mid-OAuth shouldn't put an
                // error banner behind the sheet, so swallow it and try again.
                guard let accounts = try? await APIClient.shared.request(
                    API.Destinations.connectedAccounts, as: APIResponse<[ConnectedAccount]>.self
                ).data else { continue }

                if accounts.first(where: { $0.provider == provider.rawValue })?.isConnected == true {
                    self.accounts = accounts
                    self.connectURL = nil
                    self.successMessage = "\(provider.displayName) connected."
                    return
                }
            }
        }
    }

    /// Called from the view's `onDismiss` so a hand-closed sheet doesn't leave
    /// the poll running in the background.
    func stopWatchingForConnection() {
        connectionWatchTask?.cancel()
        connectionWatchTask = nil
    }

    func disconnect(_ provider: DestinationProvider) async {
        busyProvider = provider
        errorMessage = nil
        defer { busyProvider = nil }

        do {
            _ = try await APIClient.shared.request(
                API.Destinations.disconnect(provider), as: APIResponse<EmptyData>.self
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await load()
    }
}

private struct ConnectURLResponse: Decodable {
    let url: URL
}
