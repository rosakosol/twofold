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

                        NavigationLink {
                            PartnerSetupView()
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

                    SectionCard {
                        Button {
                            if appModel.isPremiumLocked {
                                showingExportPremiumGate = true
                            } else {
                                showingExportHistory = true
                            }
                        } label: {
                            SettingsRow(title: "Export your story", systemImage: "square.and.arrow.up.on.square")
                        }
                        .buttonStyle(.plain)
                    }

                    SectionCard {
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
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
