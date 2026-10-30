import SwiftUI

/// Reached from Settings → Subscription — the wireframe's My Account →
/// Settings → Subscription/Payment screens, which didn't exist anywhere in
/// the app before this. Real plan list (GET /subscription/activeplans);
/// the free "Trial Subscription" plan purchases directly against its own
/// endpoint, and paid plans go through whichever route
/// `StoreKitStore.purchaseRoute` allows — Apple's in-app purchase, a link out
/// to the website on the US storefront, or neither. Never Stripe: that is the
/// Guideline 3.1.1 violation this screen used to ship.
struct PlansView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = PlansViewModel()
    @StateObject private var storeKit = StoreKitStore()
    @Environment(\.openURL) private var openURL
    @State private var isShowingCancelConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.plans.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if viewModel.plans.isEmpty {
                    emptyState
                } else {
                    // Outside the empty state: cancelSubscription() writes its
                    // failure to errorMessage, which was only rendered inside
                    // `emptyState` — so a failed cancellation produced no
                    // feedback at all while the plan list was populated.
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.warningGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(viewModel.plans) { plan in
                        planCard(plan)
                    }

                    // Only shown to someone who actually has a paid
                    // subscription to cancel. It used to render for everyone,
                    // including users with no subscription at all.
                    if viewModel.currentPlanId != nil, !viewModel.currentPlanIsFree {
                        cancelSubscriptionButton
                    }

                    if viewModel.useExternalPurchaseLink {
                        Text("Subscribing opens streamr.nyc in your browser. Your plan appears here once payment completes.")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }

                    // Said up front rather than only after a tap, so nobody
                    // picks a plan and then finds out. Carries no link and
                    // names no website: this branch is every storefront where
                    // pointing at one would itself breach the anti-steering
                    // rule, which is why there is nothing better to offer.
                    if viewModel.route == .unavailable {
                        Text(PlansViewModel.purchaseUnavailableMessage)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.warningGold)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }

                    // Apple requires a visible restore control on any app
                    // selling subscriptions — review rejects under 3.1.1
                    // without one even when the purchase flow itself is
                    // correct. Shown only on the Apple route, since there is
                    // nothing for StoreKit to restore otherwise.
                    if viewModel.useApplePurchasing {
                        Button {
                            Task { await storeKit.restore() }
                        } label: {
                            Text("Restore Purchases")
                                .font(StreamrFont.caption())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
        }
        .streamrBackground()
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Which plan the user is on comes from the cached login payload —
            // the same place the website reads it from. See User.purchasedplan.
            let current = authManager.currentUser?.purchasedplan?.plan
            viewModel.currentPlanId = current?.id
            viewModel.currentPlanIsFree = current?.isFree ?? true
            await viewModel.load()

            // Ask Apple for the paid plans, then take whichever route Apple's
            // answer permits. One assignment, because the alternative was two
            // booleans whose "neither" case quietly fell through to Stripe
            // card entry -- see StoreKitStore.PurchaseRoute.
            await storeKit.load(plans: viewModel.plans)
            viewModel.route = storeKit.purchaseRoute

            // Where the Streamr account gets told about an Apple purchase.
            // Nothing to call yet: no endpoint accepts an App Store
            // transaction (checked 2026-10-22). Left explicit so the gap is
            // visible in code rather than implied by its absence.
            storeKit.onPurchaseVerified = { _ in
                await viewModel.reloadAfterApplePurchase()
            }
        }
        // Driven by the view model so the plan card's own button starts it,
        // rather than a second set of buttons that could disagree about which
        // plan is current.
        .onChange(of: viewModel.externalPurchasePlan) { _, plan in
            guard plan != nil else { return }
            viewModel.externalPurchasePlan = nil
            // Leaves the app to Safari rather than opening a webview. A sheet
            // in-app would read as an in-app purchase flow, which is the thing
            // Guideline 3.1.1 is about.
            openURL(StoreKitStore.externalPurchaseURL)
        }
        .onChange(of: viewModel.applePurchasePlan) { _, plan in
            guard let plan, let product = storeKit.product(for: plan) else { return }
            viewModel.applePurchasePlan = nil
            Task { await storeKit.purchase(product) }
        }
        .alert("Purchase", isPresented: Binding(
            get: { storeKit.errorMessage != nil },
            set: { if !$0 { storeKit.errorMessage = nil } }
        )) {
            Button("OK") { storeKit.errorMessage = nil }
        } message: {
            Text(storeKit.errorMessage ?? "")
        }
        .alert(
            "Success",
            isPresented: Binding(
                get: { viewModel.purchaseSuccessMessage != nil },
                set: { if !$0 { viewModel.purchaseSuccessMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.purchaseSuccessMessage = nil }
        } message: {
            Text(viewModel.purchaseSuccessMessage ?? "")
        }
        .alert("Cancel Subscription?", isPresented: $isShowingCancelConfirmation) {
            Button("Not Now", role: .cancel) {}
            Button("Cancel Subscription", role: .destructive) {
                Task { await viewModel.cancelSubscription() }
            }
        } message: {
            Text("This cancels your current plan. You can resubscribe any time.")
        }
    }

    private var cancelSubscriptionButton: some View {
        Button {
            isShowingCancelConfirmation = true
        } label: {
            ZStack {
                Text("Cancel Subscription").opacity(viewModel.isCancelling ? 0 : 1)
                if viewModel.isCancelling { ProgressView().tint(StreamrColor.liveRed) }
            }
            .font(StreamrFont.body(15))
            .foregroundStyle(StreamrColor.liveRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .disabled(viewModel.isCancelling)
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.name)
                .font(StreamrFont.headline(17))
                .foregroundStyle(.white)

            if let description = plan.description, !description.isEmpty {
                Text(description)
                    .font(StreamrFont.body(14))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(plan.isFree ? "Free" : "$\(String(format: "%.2f", plan.amount)) / \(plan.validity)")
                .font(StreamrFont.title(20))
                .foregroundStyle(StreamrColor.primary)

            HStack(spacing: 16) {
                Label("\(plan.noofstreams) \(plan.noofstreams == 1 ? "stream" : "streams")", systemImage: "dot.radiowaves.left.and.right")
                Label("\(plan.streamMaxMinutes) min", systemImage: "clock")
            }
            .font(StreamrFont.caption())
            .foregroundStyle(.white.opacity(0.6))

            if let additionalDetails = plan.additionalDetails, !additionalDetails.isEmpty {
                Text(additionalDetails)
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            PrimaryButton(
                title: planActionTitle(plan),
                isLoading: viewModel.purchasingPlanId == plan.id
            ) {
                viewModel.selectPlan(plan)
            }
            .disabled(
                viewModel.purchasingPlanId != nil
                    || viewModel.isCurrentPlan(plan)
                    || !viewModel.canSelect(plan)
            )
            .opacity(viewModel.isCurrentPlan(plan) || !viewModel.canSelect(plan) ? 0.6 : 1)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        // The plan you're on is marked by its border too, not only by the
        // button label — colour and text alone shouldn't carry state.
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    viewModel.isCurrentPlan(plan) ? StreamrColor.primary : .clear,
                    lineWidth: 2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// No plan was marked as the subscriber's own, so every card read "Choose
    /// Plan" — including the one they were already paying for, which they could
    /// tap and be charged for a second time.
    private func planActionTitle(_ plan: SubscriptionPlan) -> String {
        if viewModel.isCurrentPlan(plan) { return "Current Plan" }
        if plan.isFree { return "Start Free" }

        switch viewModel.route {
        case .externalLink:
            // Say where the person is about to end up. Tapping this leaves the
            // app for Safari, and a button that said "Choose Plan" and then
            // threw them into a browser would be a small lie.
            return "Subscribe on the Web"
        case .unavailable:
            // Paired with the disabled state above, and with the explanation
            // under the list — the label alone shouldn't have to carry why.
            return "Unavailable"
        case .apple:
            // An existing paid subscriber switches plans rather than buying
            // afresh; Apple treats both as the same subscription group.
            if viewModel.currentPlanId != nil, !viewModel.currentPlanIsFree { return "Switch to This Plan" }
            return "Choose Plan"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(viewModel.errorMessage ?? "No plans available right now.")
                .font(StreamrFont.body())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
