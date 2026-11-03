//
//  HomeSubscriptionCards.swift
//  Twofold
//
//  Home's two cards for an account without a subscription: the general one, and the one that
//  says it was the partner who was paying.
//

import SwiftUI

/// Why access changed, for somebody who did not choose it.
///
/// `leave_couple` records this on the non-payer's profile when the partner who was covering the
/// subscription disconnects. It used to be a full-screen takeover shown in place of the forced
/// paywall — which was the right instinct in the wrong shape: the takeover appeared once, and
/// its "Not now" cleared the flag permanently, so anyone who tapped it and came back a week
/// later found a paywall and no explanation. With the wall gone there is nothing to take over
/// anyway.
///
/// A card instead, sitting above the partner cards because it explains something that has just
/// happened where those are about what to do next. It stays until dismissed, and dismissing it
/// costs nothing now: the app is still there underneath.
struct SubscriptionLapsedCard: View {
    let partnerName: String
    let onSeePlans: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Your subscription has ended", systemImage: "person.badge.minus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(partnerName) was covering your Twofold subscription, and your connection with them has ended. Nothing has been deleted — your trips, memories and photos are in Settings → Help → Archived data, and you can export them from there.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Named rather than left to be discovered. An archive is deleted ninety days after
                // the connection ends, and somebody who has just been told their subscription
                // stopped is exactly the person who will not go looking for that date.
                Text("An archive is kept for 90 days and then permanently deleted. The date is shown on it.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // One action, and no dismiss. This is the state of the account rather than an
                // announcement that has been made and is over, so it goes when the state does —
                // see the `canAddContent` check that now wraps both of these cards. Same shape as
                // `noSubscriptionCard`, which it stands in for.
                Button("See plans", action: onSeePlans)
                    .buttonStyle(.twofoldPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What is true of the app right now, for somebody without a subscription.
///
/// The prompts on each gated action explain themselves when tapped, but only to somebody who
/// tapped — this is for the person opening the app and wondering why it feels different.
/// Deliberately not dismissable: it is not an announcement that has been made and is over, it
/// is the state of the account, and it disappears on its own when that changes.
struct NoSubscriptionCard: View {
    let onSeePlans: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("No active subscription", systemImage: "lock.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Everything you've already saved is still here, and always will be — you can read it, export it and delete it at any time. What needs a subscription is adding to it: new trips, memories, flights and today's question.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("See plans", action: onSeePlans)
                    .buttonStyle(.twofoldPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
