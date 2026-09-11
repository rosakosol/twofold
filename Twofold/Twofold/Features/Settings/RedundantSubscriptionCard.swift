//
//  RedundantSubscriptionCard.swift
//  Twofold
//
//  Shown when a couple is paying for two subscriptions where one would do.
//
//  A Twofold subscription covers the couple — `private.couple_effective_tier` takes the better of
//  the two partners' tiers — so when two people who each subscribed while single connect, one of
//  those payments immediately stops buying anything. Nothing about the app changes, which is
//  precisely why nobody notices.
//
//  Settings only, directly under the subscription banner, because the action it suggests is the
//  one that banner opens. It used to appear on Home as well — dismissibly — on the reasoning that
//  the people it applies to have no reason to open Settings and will otherwise keep paying twice
//  indefinitely. That was traded away deliberately: it is a rare state, and Home's space goes to
//  what every couple needs rather than what a few do. The cost is that this is now only found by
//  someone already going looking.
//

import SwiftUI

struct RedundantSubscriptionCard: View {
    let state: BackendService.RedundantSubscription
    let partnerName: String
    /// What the action button says. It differs by where the card is: in Settings the button opens
    /// the Customer Center directly, and from Home it can only get as far as Settings, so it says
    /// so rather than promising a screen it doesn't open.
    var actionTitle: String = "Manage subscription"
    /// Leads to Apple's own flow, wherever that is from here. This card never cancels anything
    /// itself.
    let onManage: () -> Void
    /// Home only. Settings has no dismiss — that screen is where you go to look for this, so
    /// hiding it there would only make it impossible to find again.
    var onDismiss: (() -> Void)?

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .foregroundStyle(Theme.skyBlue)
                    Text("You're both subscribed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    if let onDismiss {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.subtleInk.opacity(0.5))
                                // The glyph is ~22pt, half Apple's 44pt minimum. The frame only
                                // grows the tap target; `contentShape` makes all of it hittable.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Cancels the padding the 44pt box adds, so the icon sits where it looks
                        // like it should against the card's edge.
                        .padding(.trailing, -Theme.Spacing.xs)
                        .padding(.vertical, -Theme.Spacing.sm)
                        .accessibilityLabel("Dismiss")
                    }
                }

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                // Only offered to the person who would be doing the cancelling. Someone whose
                // partner holds the later subscription can't cancel it for them, and a button
                // that opens their own plan would be an invitation to cancel the wrong one.
                if state.iAmRedundant {
                    Button(actionTitle, action: onManage)
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Three states, and the difference between them is who is being asked to do something.
    ///
    /// The last one exists because the purchase dates are not always comparable — RevenueCat may
    /// not have told us when a subscription started (see `resolveStartedAt`). Naming someone on a
    /// guess would ask a person to cancel a subscription they meant to keep, so when we don't
    /// know, we say what we do know and let them work out the rest between themselves.
    ///
    /// "Stops the next payment" rather than "cancel", deliberately. The first thing anyone thinks
    /// on being told to cancel something they have already paid for is that they are about to lose
    /// the rest of it, and that isn't what happens: cancelling an App Store subscription stops the
    /// renewal, and the entitlement runs to the end of the period already paid for. Between that
    /// and their partner's subscription, nothing they can use goes away at any point. Saying so is
    /// the difference between a suggestion someone acts on and one they ignore.
    private var message: String {
        if state.iAmRedundant {
            return "One subscription covers you both, and \(partnerName)'s started first — so yours isn't buying anything extra. Cancelling stops your next payment and takes nothing away: you keep everything through \(partnerName)'s."
        }
        if state.partnerIsRedundant {
            return "One subscription covers you both, and yours started first. \(partnerName) can stop their next payment without either of you losing anything."
        }
        return "One subscription covers you both, so the second one isn't buying anything extra. Whichever of you cancels stops their next payment, and neither of you loses anything."
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        RedundantSubscriptionCard(
            state: .init(bothSubscribed: true, redundantProfileID: UUID(), iAmRedundant: true),
            partnerName: "Alex"
        ) {}
        RedundantSubscriptionCard(
            state: .init(bothSubscribed: true, redundantProfileID: UUID(), iAmRedundant: true),
            partnerName: "Alex",
            actionTitle: "Manage in Settings",
            onManage: {},
            onDismiss: {}
        )
        RedundantSubscriptionCard(
            state: .init(bothSubscribed: true, redundantProfileID: UUID(), iAmRedundant: false),
            partnerName: "Alex"
        ) {}
        RedundantSubscriptionCard(
            state: .init(bothSubscribed: true, redundantProfileID: nil, iAmRedundant: false),
            partnerName: "Alex"
        ) {}
    }
    .padding()
    .background(Theme.backgroundGradient)
}
