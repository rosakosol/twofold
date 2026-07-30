//
//  SettingsView.swift
//  Twofold
//
//  Reached from HomeView's toolbar avatar. Top-level profile/settings shell — each row pushes
//  a focused, single-purpose screen rather than everything living inline here as it used to.
//  Own-profile editing lives in AboutYouView, couple-level settings in AboutRelationshipView,
//  and everything partner-relationship-scoped (connect, edit, archive, remove) lives in
//  PartnerSetupView, reachable both pre- and post-connection.
//

import PostHog
import RevenueCatUI
import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showingPaywall = false
    /// RevenueCat's self-service subscription management screen — offered instead of the
    /// paywall once someone's already subscribed, since re-showing "buy Plus/Premium" to a
    /// paying member makes no sense; see the "Manage subscription" row below. Only shown when
    /// this device's own RevenueCat entitlement is actually what's backing the couple's access
    /// — `CustomerCenterView` only knows about *this device's* purchase history, so for whichever
    /// partner didn't personally buy it, it'd otherwise show a bare "no subscription" screen even
    /// though the couple is genuinely covered. See `subscriptionStore`/`PartnerManagesSubscriptionView`.
    @State private var showingCustomerCenter = false
    @State private var showingPartnerManagesSubscription = false
    @State private var subscriptionStore = SubscriptionStore()
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var showingExportHistory = false
    @State private var showingExportPremiumGate = false
    @State private var appLock = AppLockService()
    @State private var isAuthenticatingLockToggle = false
    @State private var showingLockEnabledConfirmation = false
    /// `PartnerSetupView` owns its own `NavigationStack` (it's shared with Home's pre-connection
    /// entry point, which presents it as a sheet) — pushing it via `NavigationLink` onto this
    /// screen's stack would nest two `NavigationStack`s, which SwiftUI doesn't support.
    @State private var showingPartnerSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    SectionCard {
                        NavigationLink {
                            AboutYouView()
                        } label: {
                            SettingsRow(title: "About you", systemImage: "person.fill")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            AboutRelationshipView()
                        } label: {
                            SettingsRow(title: "About your relationship", systemImage: "heart.fill")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            showingPartnerSetup = true
                        } label: {
                            SettingsRow(
                                title: appModel.partnerConnected ? "About your partner" : "Connect with your partner",
                                systemImage: appModel.partnerConnected ? "person.fill.checkmark" : "person.fill.badge.plus"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SubscriptionBanner(isSubscribed: appModel.isSubscriptionActive) {
                        if appModel.isSubscriptionActive {
                            if subscriptionStore.isSubscribed {
                                showingCustomerCenter = true
                            } else {
                                showingPartnerManagesSubscription = true
                            }
                        } else {
                            showingPaywall = true
                        }
                    }

                    // TEMP: "Export your story" pulled from Settings for the first release —
                    // the feature itself (`ExportHistoryView`/`CoupleHistoryPDFExporter`, the
                    // `showingExportHistory`/`showingExportPremiumGate` state below, and their
                    // `.navigationDestination`/`.sheet` further down) is untouched, so restoring
                    // this row is the only thing needed to bring it back.
                    // SectionCard {
                    //     Button {
                    //         if appModel.isPremiumLocked {
                    //             showingExportPremiumGate = true
                    //         } else {
                    //             showingExportHistory = true
                    //         }
                    //     } label: {
                    //         SettingsRow(title: "Export your story", systemImage: "square.and.arrow.up.on.square")
                    //     }
                    //     .buttonStyle(.plain)
                    // }

                    SectionCard {
                        NavigationLink {
                            AppearanceSettingsView()
                        } label: {
                            SettingsRow(title: "Appearance", systemImage: "circle.righthalf.filled", value: AppearancePreference.current.displayName)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            MeasurementsSettingsView()
                        } label: {
                            SettingsRow(title: "Measurements", systemImage: "ruler.fill", value: MeasurementPreference.current.displayName)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            LocationPermissionView()
                        } label: {
                            SettingsRow(title: "Location permission", systemImage: "location.fill")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            NotificationPreferencesView()
                        } label: {
                            SettingsRow(title: "Notifications", systemImage: "bell.fill")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        HStack {
                            Label("Require \(appLock.methodName)", systemImage: "lock.fill")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Toggle(
                                "",
                                // Never writes `appLock.isEnabled` directly — turning this on *or*
                                // off now requires actually passing Face ID/Touch ID/passcode
                                // first (previously either direction was a bare toggle flip, so
                                // anyone holding the unlocked phone could disable the lock without
                                // proving anything). The binding's `get` always reflects the real,
                                // unchanged `isEnabled` until `requestLockToggle` authenticates and
                                // applies it, so a cancelled/failed prompt just springs the switch
                                // back to where it was.
                                isOn: Binding(
                                    get: { appLock.isEnabled },
                                    set: { requestLockToggle($0) }
                                )
                            )
                            .labelsHidden()
                            .disabled(!appLock.isAvailableOnDevice || isAuthenticatingLockToggle)
                            .accessibilityLabel("Require \(appLock.methodName)")
                        }
                        // Same reasoning as `AboutYouView`'s account-scoped rows: this is a
                        // device preference (UserDefaults, not synced), so it's fine to live
                        // right alongside Measurements/Notifications rather than a whole separate
                        // "Privacy & Security" section for one row.
                        if !appLock.isAvailableOnDevice {
                            Text("Set a passcode on this device to turn this on.")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }

                    SectionCard {
                        NavigationLink {
                            AboutUsView()
                        } label: {
                            SettingsRow(title: "About us", systemImage: "info.circle.fill")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            requestReview()
                        } label: {
                            SettingsRow(title: "Rate us 5 stars", systemImage: "star.fill", showsChevron: false)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        ShareLink(item: URL(string: "https://www.twofoldapp.com.au")!) {
                            SettingsRow(title: "Share the app", systemImage: "square.and.arrow.up", showsChevron: false)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            HelpView()
                        } label: {
                            SettingsRow(title: "Help", systemImage: "questionmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    SectionCard {
                        Button(role: .destructive) {
                            showingSignOutConfirm = true
                        } label: {
                            HStack {
                                if isSigningOut {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Text("Sign Out").frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .disabled(isSigningOut)
                        // Attached directly to this button (not down on the whole `NavigationStack`,
                        // where it lived before) — on iPad, `confirmationDialog` renders as a
                        // popover anchored to whatever view it's declared on. Declared this far
                        // from the actual button, with no way to infer a real anchor, it fell back
                        // to a fixed spot near the top of the screen instead of pointing at the
                        // Sign Out button itself. Attaching it here gives it a real anchor to point
                        // from, and changes nothing about the plain bottom-sheet behavior this
                        // already had on iPhone.
                        .confirmationDialog("Sign out of Twofold?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                            Button("Sign Out", role: .destructive) {
                                Task {
                                    isSigningOut = true
                                    await appModel.signOut()
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }

                    SettingsFooterView()
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .postHogScreenView("Settings")
            .task {
                await subscriptionStore.refreshEntitlementsOnly()
            }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack { PaywallView() }
                    .postHogScreenView("Paywall: Settings")
            }
            .sheet(isPresented: $showingCustomerCenter) {
                CustomerCenterView()
                    .postHogScreenView("Settings: Manage Subscription")
            }
            // A plan change made *inside* the Customer Center (e.g. Plus → Premium) never reaches
            // `AppModel.subscriptionTier` the way a fresh `PaywallView` purchase does — that path
            // calls `markSubscriptionActive(tier:)` directly; this one only updates RevenueCat's
            // own entitlement state, which otherwise doesn't reach `AppModel` until the next full
            // profile fetch (a server-side RevenueCat-webhook-to-Supabase round trip this device
            // doesn't control the timing of). Left stale, that's exactly "upgraded to Premium but
            // tier-gated UI — this device's own widgets included — still reads Plus."
            .onChange(of: showingCustomerCenter) { wasShowing, isShowing in
                guard wasShowing, !isShowing else { return }
                Task { await syncSubscriptionAfterCustomerCenter() }
            }
            .sheet(isPresented: $showingPartnerManagesSubscription) {
                PartnerManagesSubscriptionView(partnerName: appModel.partner.name) {
                    showingPartnerManagesSubscription = false
                }
                .postHogScreenView("Settings: Partner Manages Subscription")
            }
            .navigationDestination(isPresented: $showingExportHistory) {
                ExportHistoryView()
            }
            .sheet(isPresented: $showingExportPremiumGate) {
                FlightPremiumGateView(
                    icon: "square.and.arrow.up.on.square",
                    title: "Export Your Story",
                    description: "Turn your trips, memories, and flights into a beautiful, formatted keepsake PDF. Upgrade to Premium to export your story."
                )
            }
            .sheet(isPresented: $showingLockEnabledConfirmation) {
                AppLockEnabledConfirmationView(methodName: appLock.methodName)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPartnerSetup) {
                PartnerSetupView()
                    .postHogScreenView("Settings: Partner Setup")
            }
        }
    }

    /// Shared by both directions of the toggle — enabling and disabling each need their own
    /// fresh authentication (see the toggle's own comment). Only ever applies the new value to
    /// `appLock.isEnabled` after that succeeds; a cancelled or failed prompt leaves the setting
    /// exactly as it was.
    private func requestLockToggle(_ newValue: Bool) {
        guard !isAuthenticatingLockToggle else { return }
        isAuthenticatingLockToggle = true
        Task {
            let success = await appLock.authenticate()
            isAuthenticatingLockToggle = false
            guard success else { return }
            appLock.isEnabled = newValue
            if newValue {
                showingLockEnabledConfirmation = true
            }
        }
    }

    /// `AppStore.requestReview` is an opportunistic, OS-throttled prompt (a handful of times per
    /// year per device, no completion callback) — Apple doesn't guarantee it shows anything, so
    /// this row can appear to do nothing even when wired correctly. Once Twofold has a real App
    /// Store listing, switch this to a direct `.../id<APP_ID>?action=write-review` link instead —
    /// reliable every tap, appropriate for an explicit "Rate us" CTA (vs. an automatic nudge).
    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        AppStore.requestReview(in: scene)
    }

    /// Re-checks RevenueCat's own entitlement state right after the Customer Center closes and
    /// bridges any change into `AppModel` immediately, the same way `PaywallView` already does
    /// right after a fresh purchase — see this call site's own comment for why a Customer-Center-
    /// made plan change doesn't otherwise reach `AppModel.subscriptionTier` (and therefore this
    /// device's own widgets) until some later relaunch happens to refresh it.
    private func syncSubscriptionAfterCustomerCenter() async {
        await subscriptionStore.refreshEntitlementsOnly()
        guard let tier = subscriptionStore.subscribedTier, tier.dbValue != appModel.subscriptionTier else { return }
        appModel.markSubscriptionActive(tier: tier.dbValue)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
