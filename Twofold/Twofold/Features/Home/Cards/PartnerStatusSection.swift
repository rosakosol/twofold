//
//  PartnerStatusSection.swift
//  Twofold
//
//  Home's partner card: a request waiting on this person, a request this person is waiting on,
//  or the invitation to connect at all — whichever applies, and at most one of them.
//

import SwiftUI

struct PartnerStatusSection: View {
    @Environment(AppModel.self) private var appModel

    let onReviewRequest: (BackendService.PendingConnectionRequest) -> Void
    let onShowOutgoingRequest: () -> Void
    let onSetUpPartner: () -> Void

    @ViewBuilder
    var body: some View {
        if let incomingRequest = appModel.pendingConnectionRequests.first {
            pendingConnectionRequestCard(incomingRequest)
        } else if let outgoingRequest = appModel.pendingOutgoingConnectionRequest {
            pendingOutgoingInviteCard(outgoingRequest)
        } else if appModel.needsPartnerInvite && appModel.hasResolvedOutgoingConnectionRequest {
            // Waits to be told there is no pending request before offering to send one.
            //
            // `pendingOutgoingConnectionRequest` is nil both when there is no request and
            // when the lookup has not landed, and this branch read the second as the
            // first — so an invitee arriving at Home met "Set up your partner", the one
            // thing they had already done, until the fetch caught up a moment later.
            // Nothing takes its place in the gap: no card is better than the wrong one,
            // and the gap is one round trip.
            invitePartnerCard
        }
    }

    /// "500+"/"2000+" — matches `SubscriptionTier.features`' own "N+ questions and games"
    /// copy convention (`Features/Paywall/SubscriptionStore.swift`), so this card promises
    /// exactly what the paywall itself already promises for the couple's current tier.
    private var partnerValuePropGameCount: String {
        appModel.subscriptionTier == "premium" ? "2000+" : "500+"
    }

    /// Someone has already redeemed this user's invite code and is waiting on a decision —
    /// takes over `invitePartnerCard`'s slot entirely rather than showing alongside it ("connect
    /// with your partner" and "someone wants to connect" at once would just be confusing), since
    /// responding to an already-arrived request is strictly more actionable than being pitched
    /// the feature again. Opens the focused `ConnectionRequestReviewView` (just this one
    /// request's avatar/name + Accept/Decline), not the full `PartnerSetupView` profile editor.
    private func pendingConnectionRequestCard(_ request: BackendService.PendingConnectionRequest) -> some View {
        Button {
            onReviewRequest(request)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(
                        person: Person(
                            id: request.requesterId,
                            name: request.requesterFirstName,
                            accentColor: Person.palette[0],
                            avatarURL: request.requesterAvatarURL
                        ),
                        size: 56,
                        showsRing: true
                    )

                    Text("\(request.requesterFirstName) wants to connect")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                Text("Accept to start sharing trips, flights, and memories together.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Review request")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(.white)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryCardGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The *outgoing* counterpart to `pendingConnectionRequestCard` above — I redeemed someone
    /// else's code and I'm the one waiting now. Takes over `invitePartnerCard`'s slot the same
    /// way (already invited someone; being pitched the feature again would be redundant), and
    /// opens the same `PendingConnectionApprovalView` that used to be a full-screen root gate —
    /// now just a status sheet, since there's nothing left to block here.
    private func pendingOutgoingInviteCard(_ request: BackendService.OutgoingConnectionRequest) -> some View {
        Button {
            onShowOutgoingRequest()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(
                        person: Person(
                            id: request.inviterId,
                            name: request.inviterFirstName,
                            accentColor: Person.palette[0],
                            avatarURL: request.inviterAvatarURL
                        ),
                        size: 56,
                        showsRing: true
                    )

                    Text("Invite pending with \(request.inviterFirstName)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                Text("They haven't accepted yet — feel free to explore Twofold while you wait, or send them a nudge.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("View status")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(.white)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryCardGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The prominent, primary prompt whenever there's no connected partner — pulled out of
    /// `setupChecklistCard` into its own full-weight card (rather than a small checklist row)
    /// since setting up a partner is a much bigger, more central action than the other
    /// checklist items, and opens a single focused screen covering name/photo/city/anniversary
    /// plus the actual connect step, instead of splitting that across two separate rows.
    ///
    /// Deliberately its own bold blue-gradient design (not another pale `SectionCard`) — this is
    /// the single highest-value action a solo user can take, so it gets real visual weight and
    /// copy that actually sells why, instead of reading as just another checklist item.
    ///
    /// `primaryCardGradient`, not the button gradient, with every line pure white. The button
    /// gradient turns light blue in dark mode for navy text, so white on it was 2.2:1 there, and
    /// "Get started" took the button's navy while everything around it stayed white. Same for the
    /// two partner-request cards above.
    private var invitePartnerCard: some View {
        Button {
            onSetUpPartner()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(.white.opacity(0.2))
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 56, height: 56)

                    Text("Set up your partner")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)
                }

                Text("Twofold is built for couples. Connect with your partner to unlock \(partnerValuePropGameCount) questions and games, track each other's flights, and add shared trips and memories.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Get started")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(.white)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryCardGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
