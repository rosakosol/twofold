//
//  PaywallView.swift
//  Twofold
//
//  Thin app-specific wrapper around RevenueCatUI's own `PaywallView` — the actual paywall
//  content (hero copy, plan cards, pricing, CTA) is entirely dashboard-configured in RevenueCat
//  (Offering → Paywall), not built here. This file only owns what's specific to Twofold: wiring
//  a successful purchase/restore back into `BackendService`/`AppModel`, and the couple's
//  sign-out escape hatch for `RootView`'s forced (lapsed-subscription) gate, which the prebuilt
//  paywall has no concept of.
//
//  Used both from onboarding (pushed onto the existing onboarding NavigationStack — no internal
//  stack of its own here, same convention as the rest of onboarding) and from the settings
//  "Manage subscription" sheet (wrapped in its own NavigationStack at that call site).
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
    /// `false` only for `RootView`'s forced re-subscribe gate, which isn't presented as a
    /// sheet/push and so has nothing to dismiss to — the toolbar shows "Sign Out" instead of
    /// RevenueCat's own close button in that case, as the only way out of a lapsed/no
    /// subscription.
    var isDismissable: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        // No `offering:` argument — this always renders whichever Offering is marked "current"
        // in the RevenueCat dashboard, so pricing/copy/layout changes ship without an app update.
        RevenueCatUI.PaywallView(displayCloseButton: isDismissable)
            // Fires for both RevenueCat's own close button and right after a purchase completes
            // — the one place that needs to actually call `dismiss()`, since `isDismissable`
            // already governs whether the close button exists at all.
            .onRequestedDismissal { dismiss() }
            .onPurchaseCompleted { customerInfo in
                Task { await handleEntitlementChange(customerInfo, event: Analytics.Event.purchaseComplete) }
            }
            .onRestoreCompleted { customerInfo in
                Task { await handleEntitlementChange(customerInfo, event: Analytics.Event.restoreComplete) }
            }
            .onPurchaseFailure { error in errorMessage = error.localizedDescription }
            .onRestoreFailure { error in errorMessage = error.localizedDescription }
            .onAppear {
                Analytics.capture(Analytics.Event.paywallView, properties: ["is_dismissable": isDismissable])
            }
            .toolbar {
                if !isDismissable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sign Out", role: .destructive) {
                            showingSignOutConfirm = true
                        }
                        .disabled(isSigningOut)
                    }
                }
            }
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
    }

    /// Mirrors the pre-RevenueCat purchase/restore success path: push this device's freshest
    /// entitlement state to the caller's own Supabase profile row, then update `AppModel`
    /// locally (no network round-trip) — see `AppModel.markSubscriptionActive`'s doc comment for
    /// why that local flag, not the Supabase write, is what `RootView`'s gate actually reads.
    /// A restore that found nothing to restore (`tier == nil`) intentionally writes nothing and
    /// leaves the paywall up, same as the old StoreKit flow only advancing past it when
    /// `store.isSubscribed` was actually true.
    private func handleEntitlementChange(_ customerInfo: CustomerInfo, event: String) async {
        guard let tier = SubscriptionTier.active(in: customerInfo) else { return }
        try? await BackendService.updateSubscriptionStatus(active: true, tier: tier.dbValue)
        appModel.markSubscriptionActive()
        Analytics.capture(event, properties: ["tier": tier.dbValue])
        onSubscribed()
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .environment(AppModel())
}
