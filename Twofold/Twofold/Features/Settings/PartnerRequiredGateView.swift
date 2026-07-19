//
//  PartnerRequiredGateView.swift
//  Twofold
//
//  Same shape as `DeckPremiumGateView` (icon badge, headline, subtitle) but for the
//  "this needs a connected partner, not a subscription" case — shown when tapping any
//  partner-required-locked card (Travel deck, game type, Trips/Flights empty-state hint)
//  anywhere outside Home's own deliberate "Set up your partner" entry point (which still opens
//  the full `PartnerSetupView` profile editor instead, since that's a considered setup moment,
//  not an incidental locked-card tap). Goes straight to `PartnerConnectCard` — share/redeem a
//  code — rather than routing through profile editing first.
//

import PostHog
import SwiftUI

struct PartnerRequiredGateView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.primaryButtonGradient)
                        .opacity(0.18)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.skyBlue)
                    Circle()
                        .strokeBorder(Theme.subtleInk.opacity(0.15), lineWidth: 1)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Partner required")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("This is more fun together — connect with your partner to unlock it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                PartnerConnectCard(firstName: appModel.currentUser.name, inviteCode: $appModel.inviteCode)
                    .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .postHogScreenView("Partner Required Gate")
    }
}

#Preview {
    PartnerRequiredGateView()
        .environment(AppModel())
}
