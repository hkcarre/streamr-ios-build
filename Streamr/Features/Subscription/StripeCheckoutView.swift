import StripePayments
import SwiftUI

/// Raw card-entry sheet, deliberately mirroring the website's own Stripe
/// Elements card fields (stripeCheckoutForm.tsx) rather than Stripe's newer
/// all-in-one PaymentSheet UI — same purchase flow, same two backend calls
/// (initial-payment then confirm-payment), just a native card field instead
/// of a web one. See PlansViewModel.completePaidPurchase for the request
/// sequence. Card field itself is the shared CardFieldHolder/CardEntryField
/// (Core/UI/StripeCardField.swift) — also used by AddCardView.
///
/// Method/property names here (STPPaymentCardTextField.cardParams,
/// STPAPIClient.createPaymentMethod(with:completion:), STPPaymentMethod.stripeId)
/// are written from Stripe's publicly documented iOS SDK usage, not a real
/// local compile — there's no Mac in this dev environment, same standing
/// caveat as IVSStageManager. Verify against the actual SDK on first CI
/// build and fix any signature drift.
struct StripeCheckoutView: View {
    let plan: SubscriptionPlan
    @ObservedObject var viewModel: PlansViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cardField = CardFieldHolder()
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(StreamrFont.headline(18))
                        .foregroundStyle(.white)
                    Text("$\(String(format: "%.2f", plan.amount)) / \(plan.validity)")
                        .font(StreamrFont.body(15))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text("Card details")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))

                CardEntryField(holder: cardField)
                    .frame(height: 50)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                Spacer()

                PrimaryButton(
                    title: "Pay $\(String(format: "%.2f", plan.amount))",
                    isLoading: isProcessing
                ) {
                    Task { await submit() }
                }
                .disabled(!cardField.isValid || isProcessing)
            }
            .padding(24)
            .streamrBackground()
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
    }

    private func submit() async {
        // Non-Optional in this SDK version — confirmed by a real CI compile
        // error 2026-09-28 ("initializer for conditional binding must have
        // Optional type"). It always returns *a* value, valid or not; the
        // Pay button is already disabled unless cardField.isValid, so
        // there's nothing to guard here.
        let cardParams = cardField.field.cardParams

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let params = STPPaymentMethodParams(
                card: cardParams, billingDetails: STPPaymentMethodBillingDetails(), metadata: nil
            )
            let paymentMethod = try await createStripePaymentMethod(params: params)
            try await viewModel.completePaidPurchase(plan: plan, paymentMethodId: paymentMethod.stripeId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
