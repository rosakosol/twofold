//
//  SubscriptionLapsedFromDisconnectView.swift
//  Twofold
//
//  Shown by `RootView` in place of the generic non-dismissable re-subscribe paywall, exactly
//  once, for someone whose subscription just lapsed because the partner covering it disconnected
//  — see `leave_couple`'s partner_subscription_lapse_* columns and
//  `AppModel.partnerSubscriptionLapsedPartnerName`. The generic paywall gives no reason for why
//  access disappeared; this names it, without speculating on *why* the couple disconnected (not
//  this screen's business, and possibly a sensitive breakup).
//
//  Same non-dismissable shape `PaywallView(isDismissable: false)` uses for the same root-level
//  gate — Sign Out instead of a close button, since there's otherwise no way off this screen for
//  someone who chooses not to see the paywall right now.
//

import SwiftUI

struct SubscriptionLapsedFromDisconnectView: View {
    var partnerName: String

    @Environment(AppModel.self) private var appModel
    @State private var showingPaywall = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.primaryButtonGradient)
                    .opacity(0.18)
                Image(systemName: "heart.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 96, height: 96)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Your subscription has ended")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("\(partnerName) was covering your Twofold subscription, and your connection with them has ended. Nothing about your trips, memories, or flights has been touched — they're still saved and yours.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    appModel.markPartnerSubscriptionLapseAcknowledged()
                    showingPaywall = true
                } label: {
                    Text("See Subscription Plans")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                }

                Button("Not now") {
                    appModel.markPartnerSubscriptionLapseAcknowledged()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Sign Out", role: .destructive) {
                    showingSignOutConfirm = true
                }
                .disabled(isSigningOut)
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
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView() }
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionLapsedFromDisconnectView(partnerName: "Jamie")
    }
    .environment(AppModel())
}
