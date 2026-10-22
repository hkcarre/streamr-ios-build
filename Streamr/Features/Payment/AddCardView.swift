import StripePayments
import SwiftUI

/// Confirmed live 2026-10-01, reading stripe.tsx's AddCard component
/// directly — same card-entry -> createPaymentMethod flow as subscription
/// checkout (shared CardFieldHolder/CardEntryField, Core/UI/
/// StripeCardField.swift), POSTed to /payment/methods/add instead.
struct AddCardView: View {
    @ObservedObject var viewModel: PaymentMethodsViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cardField = CardFieldHolder()
    @State private var setAsDefault = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Card details")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))

                CardEntryField(holder: cardField)
                    .frame(height: 50)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle(isOn: $setAsDefault) {
                    Text("Set as Default")
                        .font(StreamrFont.body(14))
                        .foregroundStyle(.white)
                }
                .tint(StreamrColor.primary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                Spacer()

                PrimaryButton(title: "Save Card", isLoading: isProcessing) {
                    Task { await submit() }
                }
                .disabled(!cardField.isValid || isProcessing)
            }
            .padding(24)
            .streamrBackground()
            .navigationTitle("Add Payment Method")
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
        let cardParams = cardField.field.cardParams

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let params = STPPaymentMethodParams(
                card: cardParams, billingDetails: STPPaymentMethodBillingDetails(), metadata: nil
            )
            let paymentMethod = try await createStripePaymentMethod(params: params)
            let success = await viewModel.addCard(paymentMethodId: paymentMethod.stripeId, setAsDefault: setAsDefault)
            if success {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
