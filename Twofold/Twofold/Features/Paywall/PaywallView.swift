//
//  PaywallView.swift
//  Twofold
//
//  Custom-built paywall — talks to RevenueCat's core `Purchases` SDK directly (Offerings,
//  packages, purchase, restore) rather than RevenueCatUI's prebuilt, dashboard-configured
//  component, so the design/copy lives in this app's own code instead of a paywall builder.
//
//  Used both from onboarding (pushed onto the existing onboarding NavigationStack — no internal
//  stack of its own here, same convention as the rest of onboarding) and from three sheet
//  presentations: the settings "Manage subscription" sheet, the Premium deck upsell, and a widget
//  deep link — plus RootView's forced (lapsed-subscription) gate, which swaps this in for the
//  whole app rather than sheeting/pushing it.
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    /// Called once a purchase actually completes. Onboarding uses this to advance to the
    /// success screen; the settings entry point leaves it as a no-op and just dismisses.
    /// `RootView`'s forced (lapsed-subscription) case also leaves it a no-op — that screen
    /// routes reactively off `AppModel.isSubscriptionActive` instead (see `markSubscriptionActive`).
    var onSubscribed: () -> Void = {}
    /// `false` only for `RootView`'s forced re-subscribe gate, which isn't presented as a
    /// sheet/push and so has nothing to dismiss to — the toolbar shows "Sign Out" instead of a
    /// close button in that case, as the only way out of a lapsed/no subscription.
    var isDismissable: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var store = SubscriptionStore()
    @State private var selectedTier: SubscriptionTier = .plus
    @State private var selectedPeriod: BillingPeriod = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var selectedPricedPackage: PricedPackage? {
        store.package(for: selectedTier, period: selectedPeriod)
    }

    var body: some View {
        Group {
            switch store.loadState {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                errorState(message)
            case .loaded:
                loadedContent
            }
        }
        .task {
            if store.loadState == .idle { await store.loadOfferings() }
        }
        .toolbar { toolbarContent }
        .confirmationDialog("Sign out of Twofold?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task {
                    isSigningOut = true
                    await appModel.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            Analytics.capture(Analytics.Event.paywallView, properties: ["is_dismissable": isDismissable])
        }
    }

    // MARK: - Load states

    private var loadingState: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ProgressView()
        }
    }

    private func errorState(_ message: String) -> some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.subtleInk)
                Text("Couldn't load subscription options")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                Button("Try Again") {
                    Task { await store.loadOfferings() }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.primaryButtonGradient, in: Capsule())
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Loaded content

    private var loadedContent: some View {
        OnboardingScaffold(
            title: "Choose Your Plan",
            subtitle: "Cancel anytime.",
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                            TierCard(
                                tier: tier,
                                priceCaption: priceCaption(for: tier),
                                isSelected: selectedTier == tier
                            ) {
                                selectedTier = tier
                            }
                        }
                    }

                    Picker("Billing period", selection: $selectedPeriod) {
                        Text("Monthly").tag(BillingPeriod.monthly)
                        Text(yearlyPickerLabel).tag(BillingPeriod.yearly)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(selectedTier.features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.leafGreen)
                                Text(feature)
                                    .foregroundStyle(Theme.ink)
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Restore Purchases") {
                        Task { await performRestore() }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
                    .disabled(isPurchasing || isRestoring)

                    HStack(spacing: Theme.Spacing.sm) {
                        Link("Privacy Policy", destination: URL(string: "https://www.twofoldapp.com.au/privacy.html")!)
                        Text("·").foregroundStyle(Theme.subtleInk)
                        Link("Terms of Use", destination: URL(string: "https://www.twofoldapp.com.au/terms.html")!)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                }
            },
            primaryTitle: primaryButtonTitle,
            primaryAction: { Task { await performPurchase() } },
            primaryDisabled: selectedPricedPackage == nil || isPurchasing || isRestoring,
            primaryLoading: isPurchasing
        )
    }

    private var yearlyPickerLabel: String {
        guard let monthly = store.package(for: selectedTier, period: .monthly)?.package.storeProduct,
              let yearly = store.package(for: selectedTier, period: .yearly)?.package.storeProduct else {
            return "Yearly"
        }
        let monthlyPrice = NSDecimalNumber(decimal: monthly.price).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        guard monthlyPrice > 0 else { return "Yearly" }
        let yearlyMonthlyEquivalent = yearlyPrice / 12
        let savings = Int(((monthlyPrice - yearlyMonthlyEquivalent) / monthlyPrice * 100).rounded())
        return savings > 0 ? "Yearly — Save \(savings)%" : "Yearly"
    }

    private func priceCaption(for tier: SubscriptionTier) -> String {
        guard let priced = store.package(for: tier, period: selectedPeriod) else { return "Not available" }
        let product = priced.package.storeProduct
        let periodLabel = selectedPeriod == .monthly ? "month" : "year"
        return "\(product.localizedPriceString)/\(periodLabel)"
    }

    private var primaryButtonTitle: String {
        guard let priced = selectedPricedPackage else { return "Not available" }
        let periodLabel = selectedPeriod == .monthly ? "month" : "year"
        return "Continue — \(priced.package.storeProduct.localizedPriceString)/\(periodLabel), auto-renews"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isDismissable {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button("Sign Out", role: .destructive) {
                    showingSignOutConfirm = true
                }
                .disabled(isSigningOut)
            }
        }
    }

    // MARK: - Actions

    private func performPurchase() async {
        guard let pricedPackage = selectedPricedPackage else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            guard let customerInfo = try await store.purchase(pricedPackage) else { return }
            await handleEntitlementChange(customerInfo, event: Analytics.Event.purchaseComplete)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let customerInfo = try await store.restore()
            if SubscriptionTier.active(in: customerInfo) != nil {
                await handleEntitlementChange(customerInfo, event: Analytics.Event.restoreComplete)
            } else {
                errorMessage = "No active subscription found to restore."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mirrors the pre-RevenueCat purchase/restore success path: push this device's freshest
    /// entitlement state to the caller's own Supabase profile row, then update `AppModel`
    /// locally (no network round-trip) — see `AppModel.markSubscriptionActive`'s doc comment for
    /// why that local flag, not the Supabase write, is what `RootView`'s gate actually reads.
    private func handleEntitlementChange(_ customerInfo: CustomerInfo, event: String) async {
        guard let tier = SubscriptionTier.active(in: customerInfo) else { return }
        try? await BackendService.updateSubscriptionStatus(active: true, tier: tier.dbValue)
        appModel.markSubscriptionActive()
        Analytics.capture(event, properties: ["tier": tier.dbValue])
        onSubscribed()
        // Only when reached as a dismissable sheet/push — RootView's forced gate has nothing to
        // dismiss to and already routes itself off `appModel.isSubscriptionActive` flipping.
        if isDismissable { dismiss() }
    }
}

/// A selectable plan card — tier name, its price for the currently chosen billing period, and a
/// trailing selection indicator. Similar visual language to `OnboardingCard`, but with its own
/// layout since that component has no slot for a price line.
private struct TierCard: View {
    let tier: SubscriptionTier
    let priceCaption: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(priceCaption)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.skyBlue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .environment(AppModel())
}
