import SwiftUI

/// The wireframe's "Payment" screen — saved cards + billing history, which
/// didn't exist anywhere in the app before this. Mirrors PaymentMethod.tsx:
/// GET /payment/payment-methods, POST /payment/methods/add, DELETE
/// /payment/methods/remove, POST /user/transactions.
struct PaymentMethodsView: View {
    @StateObject private var viewModel = PaymentMethodsViewModel()
    @State private var isShowingAddCard = false
    @State private var removingMethod: SavedPaymentMethod?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if viewModel.paymentMethods.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else if viewModel.paymentMethods.isEmpty {
                    Text("No saved payment methods.")
                        .font(StreamrFont.body())
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(viewModel.paymentMethods) { method in
                        paymentMethodRow(method)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(StreamrFont.caption())
                        .foregroundStyle(StreamrColor.liveRed)
                }

                billingHistory
            }
            .padding(20)
        }
        .streamrBackground()
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $isShowingAddCard) {
            AddCardView(viewModel: viewModel)
        }
        .alert("Delete this card?", isPresented: Binding(
            get: { removingMethod != nil },
            set: { if !$0 { removingMethod = nil } }
        )) {
            Button("Cancel", role: .cancel) { removingMethod = nil }
            Button("Delete", role: .destructive) {
                if let removingMethod {
                    Task { await viewModel.removeCard(removingMethod) }
                }
                removingMethod = nil
            }
        } message: {
            Text("This action cannot be undone. Your saved payment method will be permanently removed.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Payment Method")
                    .font(StreamrFont.headline(17))
                    .foregroundStyle(.white)
                Text("Manage your payment methods.")
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Button {
                isShowingAddCard = true
            } label: {
                Label("Add Card", systemImage: "plus")
                    .font(StreamrFont.caption(13))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(StreamrColor.primary)
                    .clipShape(Capsule())
            }
        }
    }

    private func paymentMethodRow(_ method: SavedPaymentMethod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .foregroundStyle(.white.opacity(0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text("•••• •••• •••• \(method.card?.last4 ?? "----")")
                    .font(StreamrFont.body(15))
                    .foregroundStyle(.white)
                if let month = method.card?.expMonth, let year = method.card?.expYear {
                    Text("Expires \(month)/\(year)")
                        .font(StreamrFont.caption())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            if method.card?.isDefault == true {
                Text("Default")
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }

            // 44x44 and labelled. This was a bare ~20pt glyph sitting a few
            // points from the "Default" capsule — an easy mis-tap on a
            // destructive control, and VoiceOver announced it only as "trash".
            Button {
                removingMethod = method
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(StreamrColor.liveRed)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(
                method.card?.last4.map { "Remove card ending \($0)" } ?? "Remove card"
            )
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var billingHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing History")
                .font(StreamrFont.headline(16))
                .foregroundStyle(.white)

            if viewModel.transactions.isEmpty {
                Text("No billing history found.")
                    .font(StreamrFont.body(14))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(Array(viewModel.transactions.enumerated()), id: \.offset) { _, transaction in
                    transactionRow(transaction)
                }
            }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate(transaction.createdAt))
                    .font(StreamrFont.body(14))
                    .foregroundStyle(.white)
                Text(transaction.displayPlanName)
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", transaction.amount ?? 0))")
                    .font(StreamrFont.headline(14))
                    .foregroundStyle(.white)
                Text(transaction.status == "succeeded" ? "Paid" : (transaction.status ?? "Paid"))
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(StreamrColor.primary)
            }
        }
        .padding(.vertical, 8)
    }

    private func formattedDate(_ raw: String?) -> String {
        guard let raw, let date = ISO8601DateFormatter().date(from: raw) else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
