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
import RevenueCatUI

struct PaywallView: View {
    /// Called once a purchase actually completes. Onboarding uses this to advance to the
    /// success screen; the settings entry point leaves it as a no-op and just dismisses.
    /// `RootView`'s forced (lapsed-subscription) case also leaves it a no-op — that screen
    /// routes reactively off `AppModel.isSubscriptionActive` instead (see `markSubscriptionActive`).
    var onSubscribed: () -> Void = {}
    /// Must be `false` for every call site that isn't a genuine `.sheet`/`.fullScreenCover` —
    /// `RootView`'s forced re-subscribe gate (also shows "Sign Out" instead of a close button
    /// there, the only way out of a lapsed/no subscription) and onboarding's pushed `.paywall`
    /// step both qualify: `handleEntitlementChange` calls `dismiss()` on success when this is
    /// `true`, and on a *pushed* destination that pops the current path entry — including
    /// popping a `.purchaseSuccess` step just appended by `onSubscribed()` in the same call,
    /// which is exactly the bug that motivated this comment. Only leave the default `true` for
    /// real modal presentations, where `dismiss()` closing the sheet is the correct behavior.
    var isDismissable: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var store = SubscriptionStore()
    @State private var selectedTier: SubscriptionTier
    @State private var selectedPeriod: BillingPeriod = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showingSignOutConfirm = false
    /// Only actually shown when this device's own RevenueCat entitlement is what's backing
    /// `effectiveActiveTier` — `CustomerCenterView` only knows this device's own purchase
    /// history, so when the couple's access instead comes from the partner's separate purchase
    /// (`isSubscribedToADifferentTier`'s own doc comment), it'd show a bare "no subscription"
    /// screen. `PartnerManagesSubscriptionView` is shown in that case instead.
    @State private var showingCustomerCenter = false
    @State private var showingPartnerManagesSubscription = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?
    /// Freshly fetched from both partners' profile rows (see `BackendService.fetchCoupleSubscriptionTier`)
    /// — `store.subscribedTier` only knows about *this* Apple ID/device, which misses a tier the
    /// partner subscribed to separately. `nil` while the fetch is in flight or if it fails, in
    /// which case the guards below fall back to this device's own local knowledge.
    @State private var coupleActiveTierFromServer: SubscriptionTier?

    /// `initialTier` lets a specific upsell (e.g. `DeckPremiumGateView`'s "Continue to Premium")
    /// land directly on the plan it's actually selling, instead of always defaulting to Plus.
    init(onSubscribed: @escaping () -> Void = {}, isDismissable: Bool = true, initialTier: SubscriptionTier = .plus) {
        self.onSubscribed = onSubscribed
        self.isDismissable = isDismissable
        _selectedTier = State(initialValue: initialTier)
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var selectedPricedPackage: PricedPackage? {
        store.package(for: selectedTier, period: selectedPeriod)
    }

    /// The tier actually active for this purchaser's *couple* right now — prefers the fresh
    /// server-side check (catches a partner's separate subscription) and falls back to this
    /// device's own local RevenueCat entitlement if that fetch hasn't completed or failed.
    private var effectiveActiveTier: SubscriptionTier? { coupleActiveTierFromServer ?? store.subscribedTier }

    /// Already on exactly the plan currently selected in the segmented control — purchasing
    /// again would be redundant, so the CTA is disabled instead of firing.
    private var isAlreadySubscribedToSelectedTier: Bool { effectiveActiveTier == selectedTier }

    /// Either this account or their partner already holds the *other* tier. App Store Connect's
    /// subscription-group exclusivity only applies within a single Apple ID — it does nothing to
    /// stop two different partners from each independently subscribing to a different tier, which
    /// is the real way this app's "one subscription per couple" design breaks (confirmed: each
    /// partner's own `subscription_tier` is written to their own profile row independently, see
    /// `BackendService.updateSubscriptionStatus`). So the CTA routes to RevenueCat's Customer
    /// Center (a real upgrade/downgrade/cancel flow) instead of ever calling `purchase` directly
    /// in this case — see `performPurchase()`'s matching guard.
    private var isSubscribedToADifferentTier: Bool {
        effectiveActiveTier != nil && effectiveActiveTier != selectedTier
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
            // Needed to know which tier (if any) is already active, so the CTA below can refuse
            // to stack a second purchase on top of it — see `isSubscribedToADifferentTier`.
            await store.refreshEntitlementsOnly()
            if let tierValue = try? await BackendService.fetchCoupleSubscriptionTier() {
                coupleActiveTierFromServer = SubscriptionTier(rawValue: tierValue)
            }
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
        .sheet(isPresented: $showingCustomerCenter) {
            CustomerCenterView()
        }
        .sheet(isPresented: $showingPartnerManagesSubscription) {
            PartnerManagesSubscriptionView(partnerName: appModel.partner.name) {
                showingPartnerManagesSubscription = false
            }
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
            titleFont: .system(.title, design: .rounded, weight: .bold),
            subtitle: "One subscription covers you and your partner",
            subtitleFont: .footnote,
            titleTopPadding: Theme.Spacing.sm,
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
            primaryTitle: primaryButtonTitle,
            primaryAction: {
                if isSubscribedToADifferentTier {
                    if store.isSubscribed {
                        showingCustomerCenter = true
                    } else {
                        showingPartnerManagesSubscription = true
                    }
                } else {
                    Task { await performPurchase() }
                }
            },
            primaryDisabled: (selectedPricedPackage == nil && !isSubscribedToADifferentTier) || isPurchasing || isRestoring || isAlreadySubscribedToSelectedTier,
            primaryLoading: isPurchasing,
            primaryCaption: isSubscribedToADifferentTier || isAlreadySubscribedToSelectedTier ? nil : trialCaption,
            footer: AnyView(legalFooter)
        )
    }

    /// One subscription per couple, ever — see `isSubscribedToADifferentTier`'s doc comment.
    /// These two states pre-empt the normal "buy it" copy so the CTA never reads as an offer to
    /// purchase a plan the user (or their partner) already holds.
    private var primaryButtonTitle: String {
        if isAlreadySubscribedToSelectedTier { return "Current Plan" }
        if isSubscribedToADifferentTier { return "Manage Subscription" }
        return selectedPricedPackage == nil ? "Not available" : "Start my 14-day free trial"
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
        // Belt-and-suspenders: the CTA above already routes to Customer Center instead of calling
        // this when a different tier is active, but never fire a purchase here either way.
        guard let pricedPackage = selectedPricedPackage, !isSubscribedToADifferentTier else { return }
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
