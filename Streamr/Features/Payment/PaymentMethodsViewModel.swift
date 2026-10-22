import Foundation

@MainActor
final class PaymentMethodsViewModel: ObservableObject {
    @Published private(set) var paymentMethods: [SavedPaymentMethod] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isProcessing = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let methods: () = loadPaymentMethods()
        async let history: () = loadTransactions()
        _ = await (methods, history)
    }

    /// Called standalone by AddCardView/delete, not just load() — re-fetches
    /// just the methods list without touching billing history or the
    /// shared isLoading flag (which would otherwise flash the full-screen
    /// spinner over an already-populated list).
    func loadPaymentMethods() async {
        do {
            let response = try await APIClient.shared.request(
                API.Payment.paymentMethods, as: PaymentMethodsResponse.self
            )
            paymentMethods = response.paymentMethods ?? []
        } catch {
            // A cancelled pull-to-refresh isn't a failure — see
            // Error.isCancellation.
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func addCard(paymentMethodId: String, setAsDefault: Bool) async -> Bool {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            _ = try await APIClient.shared.request(
                API.Payment.addPaymentMethod(paymentMethodId: paymentMethodId, setAsDefault: setAsDefault),
                as: APIResponse<EmptyData>.self
            )
            await loadPaymentMethods()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeCard(_ method: SavedPaymentMethod) async {
        errorMessage = nil
        do {
            _ = try await APIClient.shared.request(
                API.Payment.removePaymentMethod(paymentMethodId: method.id), as: APIResponse<EmptyData>.self
            )
            paymentMethods.removeAll { $0.id == method.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTransactions() async {
        do {
            let response = try await APIClient.shared.request(
                API.User.transactions(page: 1), as: APIResponse<[Transaction]>.self
            )
            transactions = response.data ?? []
        } catch {
            // Best-effort — the payment methods list above still works even
            // if billing history fails to load.
        }
    }
}
