//
//  PartnerRequiredGateView.swift
//  Twofold
//
//  Two screens in one, chosen by whether this person has already done the thing it asks for.
//
//  Someone with a connection request still pending has invited their partner and is waiting. Being
//  told to "connect with your partner" at that point reads as though the invite never happened, and
//  the connect card underneath offers to send another. So for them this becomes a status: who they
//  are waiting on, shown with the photo they chose for that person during onboarding, and the same
//  nudge the Home card offers.
//
//  For everyone else it is unchanged. Same shape as `DeckPremiumGateView` (icon badge, headline,
//  subtitle) but for the "this needs a connected partner, not a subscription" case — shown when tapping any
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

                if let pending = appModel.pendingOutgoingConnectionRequest {
                    waitingOn(pending)
                } else {
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

                    PendingConnectionRequestsCard()
                        .padding(.horizontal, Theme.Spacing.lg)

                    PartnerConnectCard(inviteCode: $appModel.inviteCode)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await appModel.refreshPendingConnectionRequests()
            }
        }
        .postHogScreenView("Partner Required Gate")
    }
}

private extension PartnerRequiredGateView {
    /// The waiting version. No invite code, no connect card — they have already sent one, and a
    /// second would only confuse the person on the other end.
    ///
    /// The photo is `appModel.partner.avatarURL`, which for someone not yet connected is the
    /// picture *they* chose for their partner during onboarding rather than anything that partner
    /// uploaded. That is the right one to show: it is who they think they are waiting for.
    @ViewBuilder
    func waitingOn(_ request: BackendService.OutgoingConnectionRequest) -> some View {
        AvatarView(
            person: Person(
                id: request.inviterId,
                name: request.inviterFirstName,
                accentColor: Person.palette[0],
                avatarURL: appModel.partner.avatarURL ?? request.inviterAvatarURL
            ),
            size: 96,
            showsRing: true
        )

        VStack(spacing: Theme.Spacing.sm) {
            Text("Waiting on \(request.inviterFirstName)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("You've sent your request — this unlocks the moment \(request.inviterFirstName) accepts. We'll let you know.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

#Preview {
    PartnerRequiredGateView()
        .environment(AppModel())
}
