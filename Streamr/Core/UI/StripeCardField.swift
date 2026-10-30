import StripePayments
import StripePaymentsUI
import SwiftUI

/// Native card-entry field (STPPaymentCardTextField), used by AddCardView to
/// save a payment method — the same raw Stripe Elements-equivalent field, not
/// Stripe's newer PaymentSheet UI, matching the website.
///
/// It once served subscription checkout too. That path is gone: charging for a
/// subscription through Stripe inside the app is what Guideline 3.1.1 forbids,
/// so paid plans go through Apple or the website. Saving a card for a
/// web-billed subscription is account management, not a purchase, which is why
/// this field survives.
///
/// Holds the actual STPPaymentCardTextField instance (not a SwiftUI-owned
/// copy) so callers read its live `.cardParams` at submit time — avoids
/// round-tripping card data through a two-way SwiftUI binding on every
/// keystroke, which risks fighting the field's own internal state.
@MainActor
final class CardFieldHolder: ObservableObject {
    let field = STPPaymentCardTextField()
    @Published var isValid = false
}

struct CardEntryField: UIViewRepresentable {
    let holder: CardFieldHolder

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        holder.field.delegate = context.coordinator
        return holder.field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(holder: holder) }

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        let holder: CardFieldHolder
        init(holder: CardFieldHolder) { self.holder = holder }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            holder.isValid = textField.isValid
        }
    }
}

/// Wraps STPAPIClient's completion-handler createPaymentMethod API rather
/// than betting on a specific async overload existing in whatever SDK
/// version CI resolves — this completion-handler shape has been stable
/// across Stripe's iOS SDK for a long time, unlike newer async additions.
func createStripePaymentMethod(params: STPPaymentMethodParams) async throws -> STPPaymentMethod {
    try await withCheckedThrowingContinuation { continuation in
        STPAPIClient.shared.createPaymentMethod(with: params) { paymentMethod, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let paymentMethod {
                continuation.resume(returning: paymentMethod)
            } else {
                continuation.resume(throwing: APIError.server(
                    message: "Stripe didn't return a payment method.", statusCode: 0
                ))
            }
        }
    }
}
