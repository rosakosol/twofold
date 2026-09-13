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
    /// Nil until looked up, and left nil if the lookup fails — this card is an FYI about money,
    /// and a failed query is not a reason to tell anyone anything.
    @State private var redundantSubscription: BackendService.RedundantSubscription?
    @State private var subscriptionStore = SubscriptionStore()
    /// True once *both* of the `.task`'s awaits have returned — the entitlement refresh and the
    /// redundant-subscription lookup. `subscriptionStore` is a fresh instance every time Settings
    /// is presented and `refreshEntitlementsOnly()` is a real network round trip, so every open
    /// starts from "nothing known" and the banner's subtitle is computed twice more as the two
    /// answers land. Gating on the pair means it settles once instead of changing under the reader.
    @State private var hasLoadedSubscriptionContext = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var appLock = AppLockService()
    @State private var isAuthenticatingLockToggle = false
    /// Which way the app-lock toggle just went, non-nil while the confirmation is up. Was a plain
    /// `showingLockEnabledConfirmation` bool, which could only describe the "on" direction — the
    /// "off" one had nothing to show and so showed nothing.
    @State private var lockChangeToConfirm: AppLockConfirmationView.Change?
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

                    // Subscribed if *either* source says so, the same three-way reading RootView's
                    // paywall gate uses.
                    //
                    // This read only `isSubscriptionActive`, the column the RevenueCat webhook
                    // writes. Between paying and that webhook landing — or while it is
                    // misconfigured, or if it never retried — a real subscriber was told to
                    // "Unlock Twofold Plus", something they had already done and could not do
                    // again. `subscriptionStore.isSubscribed` is RevenueCat's own answer on this
                    // device, receipt-validated, and it is available immediately.
                    SubscriptionBanner(
                        isSubscribed: appModel.isSubscriptionActive || subscriptionStore.isSubscribed,
                        coverageNote: subscriptionCoverageNote
                    ) {
                        if subscriptionStore.isSubscribed {
                            // Bought on this device, so this is the one place it can be changed.
                            showingCustomerCenter = true
                        } else if appModel.isSubscriptionActive {
                            // Covered, but not from here — the partner holds it.
                            showingPartnerManagesSubscription = true
                        } else {
                            showingPaywall = true
                        }
                    }

                    // Directly under the banner, because the action it suggests is the one the
                    // banner opens.
                    if let redundantSubscription, redundantSubscription.bothSubscribed {
                        RedundantSubscriptionCard(
                            state: redundantSubscription,
                            partnerName: appModel.partner.name
                        ) {
                            showingCustomerCenter = true
                        }
                    }

                    // Ungated and partner-only, unlike the Relationship Record below it. That one
                    // is a keepsake and can be a Premium perk; this is the complete copy, and a
                    // portability request does not care what anyone is paying. Until it existed
                    // the full export lived only in Archived Data, which meant you could not have
                    // your own data until the relationship had ended.
                    if appModel.partnerConnected {
                        SectionCard {
                            NavigationLink {
                                ExportDataView()
                            } label: {
                                SettingsRow(title: "Export your data", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Premium, and partner-only: it is a record of a shared history, so there
                    // has to be one. Locked rather than hidden — someone on Plus should be able to
                    // see what they would be getting.
                    if appModel.partnerConnected {
                        SectionCard {
                            if appModel.isPremiumLocked {
                                Button { showingPaywall = true } label: {
                                    SettingsRow(
                                        title: "Your Relationship Record",
                                        systemImage: "book.closed.fill",
                                        value: "Premium"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    RelationshipTimelineView()
                                } label: {
                                    SettingsRow(title: "Your Relationship Record", systemImage: "book.closed.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

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
                redundantSubscription = try? await BackendService.redundantSubscription()
                hasLoadedSubscriptionContext = true
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
            .sheet(item: $lockChangeToConfirm) { change in
                // Detents are set inside the view — see its own comment; the choice depends on
                // the text size, which is only in scope there.
                AppLockConfirmationView(change: change, methodName: appLock.methodName)
            }
            .sheet(isPresented: $showingPartnerSetup) {
                PartnerSetupView()
                    .postHogScreenView("Settings: Partner Setup")
            }
        }
    }

    /// Names the partner whose subscription is covering the couple, as the banner's subtitle.
    ///
    /// A Twofold subscription covers the couple — `private.couple_effective_tier` takes the better
    /// of the two partners' tiers — so for the person who did not buy it, the banner's default
    /// subtitle ("View or change your plan") describes something they cannot actually do from
    /// here; tapping it explains the partner holds it. Naming them up front saves that detour.
    ///
    /// Only that direction. This used to have a matching "One subscription covers you both — this
    /// one's yours" for the person who *did* buy it, which said nothing the banner above it wasn't
    /// already saying, and paid for it by being the one line on the screen that arrived late.
    ///
    /// Nil until `hasLoadedSubscriptionContext`. Both of the values below start at their
    /// "not subscribed / no redundancy" defaults, which are indistinguishable from "not asked
    /// yet", so an ungated read names nobody, then names the partner, then possibly takes it back
    /// when the redundancy lookup lands — the flicker this gate exists to stop.
    ///
    /// Nil too while both are subscribed: the redundant-subscription card below owns that state,
    /// and a single owner is not what is happening there.
    private var subscriptionCoverageNote: String? {
        guard appModel.partnerConnected,
              hasLoadedSubscriptionContext,
              !(redundantSubscription?.bothSubscribed ?? false),
              appModel.isSubscriptionActive,
              !subscriptionStore.isSubscribed
        else { return nil }

        return "\(appModel.partner.name)'s subscription covers you both"
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
            // Both directions, not just "on". Turning the lock off is the change that removes a
            // protection, so it's the one most worth confirming out loud.
            lockChangeToConfirm = newValue ? .enabled : .disabled
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
