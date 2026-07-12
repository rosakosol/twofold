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

import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showingPaywall = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false

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
                        showingPaywall = true
                    }

                    SectionCard {
                        NavigationLink {
                            WidgetsCatalogView()
                        } label: {
                            SettingsRow(title: "Widgets", systemImage: "square.grid.2x2.fill")
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

                        SettingsRow(title: "Language", systemImage: "globe", showsChevron: false, unavailableBadge: "Not available yet")
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

                        SettingsRow(title: "Help", systemImage: "questionmark.circle.fill", showsChevron: false, unavailableBadge: "Not available yet")
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
            .sheet(isPresented: $showingPaywall) {
                NavigationStack { PaywallView() }
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

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        AppStore.requestReview(in: scene)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
