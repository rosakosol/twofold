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
            title: "Stay close, no matter the distance",
            titleAccessoryImageName: "GlobeHeart",
            titleFont: .system(.title2, design: .rounded, weight: .bold),
            subtitle: "One subscription covers you and your partner",
            subtitleFont: .footnote,
            centersTitleAndSubtitle: true,
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    VStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: 4) {
                            Text("Best for frequent flyers")
                            Image(systemName: "arrow.down")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.heartRed)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Theme.Spacing.md)

                        Picker("Plan", selection: $selectedTier) {
                            ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                                Text(tier.displayName).tag(tier)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
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
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(BillingPeriod.allCases, id: \.self) { period in
                            PeriodCard(
                                title: periodTitle(for: period),
                                priceCaption: priceCaption(for: period),
                                perPersonCaption: perPersonCaption(for: period),
                                badge: savingsBadge(for: period),
                                isSelected: selectedPeriod == period
                            ) {
                                selectedPeriod = period
                            }
                        }
                    }
                }
            },
            primaryTitle: selectedPricedPackage == nil ? "Not available" : "Start my 14-day free trial",
            primaryAction: { Task { await performPurchase() } },
            primaryDisabled: selectedPricedPackage == nil || isPurchasing || isRestoring,
            primaryLoading: isPurchasing,
            primaryCaption: trialCaption,
            footer: AnyView(legalFooter)
        )
    }

    private var legalFooter: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button("Restore Purchases") {
                Task { await performRestore() }
            }
            .disabled(isPurchasing || isRestoring)
            Text("·").foregroundStyle(Theme.subtleInk)
            Link("Privacy Policy", destination: URL(string: "https://www.twofoldapp.com.au/privacy.html")!)
            Text("·").foregroundStyle(Theme.subtleInk)
            Link("Terms of Use", destination: URL(string: "https://www.twofoldapp.com.au/terms.html")!)
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(Theme.subtleInk)
    }

    private func periodTitle(for period: BillingPeriod) -> String {
        period == .monthly ? "Monthly" : "Yearly"
    }

    /// "$X.XX / month for 2 users" — the actual subscription price/period, framed around the fact
    /// one subscription covers both partners.
    private func priceCaption(for period: BillingPeriod) -> String {
        guard let priced = store.package(for: selectedTier, period: period) else { return "Not available" }
        let periodLabel = period == .monthly ? "month" : "year"
        return "\(priced.package.storeProduct.localizedPriceString) / \(periodLabel) for 2 users"
    }

    /// "$X.XX / person / month" — the price normalized to a per-person, per-month rate (dividing
    /// by 12 first for the yearly card) so both cards read on the same, easily comparable basis
    /// regardless of billing period.
    private func perPersonCaption(for period: BillingPeriod) -> String? {
        guard let product = store.package(for: selectedTier, period: period)?.package.storeProduct else { return nil }
        let price = NSDecimalNumber(decimal: product.price).doubleValue
        let monthlyEquivalent = period == .monthly ? price : price / 12
        let perPerson = monthlyEquivalent / 2
        let formatted = product.priceFormatter?.string(from: NSNumber(value: perPerson))
            ?? String(format: "%.2f", perPerson)
        return "\(formatted) / person / month"
    }

    /// "14 days free, then $X.XX/month" (or /year, matching whichever period is selected) — shown
    /// as a small disclosure under the primary CTA, never hardcoded to "/month" regardless of the
    /// actual selection, since that would misstate the real renewal price for a yearly pick.
    private var trialCaption: String? {
        guard let priced = selectedPricedPackage else { return nil }
        let periodLabel = selectedPeriod == .monthly ? "month" : "year"
        return "14 days free, then \(priced.package.storeProduct.localizedPriceString)/\(periodLabel)"
    }

    /// "Save X%" badge for the yearly card, comparing its effective monthly cost against the
    /// actual monthly plan's price — `nil` (no badge) for the monthly card, or if either price
    /// isn't available yet, or there's no real saving to show.
    private func savingsBadge(for period: BillingPeriod) -> String? {
        guard period == .yearly,
              let monthly = store.package(for: selectedTier, period: .monthly)?.package.storeProduct,
              let yearly = store.package(for: selectedTier, period: .yearly)?.package.storeProduct else { return nil }
        let monthlyPrice = NSDecimalNumber(decimal: monthly.price).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        guard monthlyPrice > 0 else { return nil }
        let yearlyMonthlyEquivalent = yearlyPrice / 12
        let savings = Int(((monthlyPrice - yearlyMonthlyEquivalent) / monthlyPrice * 100).rounded())
        return savings > 0 ? "Save \(savings)%" : nil
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

/// A selectable billing-period card — shown two-up (Monthly / Yearly) side by side for whichever
/// tier is currently picked via the tab above. Optional badge slot for "Save X%" on the yearly
/// card. Similar visual language to `OnboardingCard`, but with its own layout since that
/// component has no slot for a price line or badge.
private struct PeriodCard: View {
    let title: String
    let priceCaption: String
    let perPersonCaption: String?
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.leafGreen, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(priceCaption)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if let perPersonCaption {
                        Text(perPersonCaption)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity)
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
