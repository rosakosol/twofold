//
//  StreakRepairPromptView.swift
//  Twofold
//
//  The one time each person is told their streak can be bought back.
//
//  Shown once per broken streak per person, on opening the app, and never brought up again for
//  that break — see `RootView`'s `streakRepairOfferKey`. Both partners get their own single
//  showing, because it is their streak too and neither should hear about it only from the other.
//
//  A popup interrupting someone is a strong thing to spend on a purchase, so it is spent carefully:
//  it names what was lost, offers to bring it back, and offers to leave. No countdown, no second
//  ask, nothing that keeps them here. If they close it, that break is finished as far as the app is
//  concerned.
//

import PostHog
import SwiftUI

struct StreakRepairPromptView: View {
    let streak: Int
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = StreakRepairStore()

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.primaryButtonGradient)
                    .opacity(0.18)
                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.heartRed)
            }
            .frame(width: 96, height: 96)

            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                if case .repaired = store.phase {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Button {
                        Task { await repairNow() }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if isWorking { ProgressView().controlSize(.small).tint(.white) }
                            Text(primaryTitle)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .disabled(isWorking)

                    // Plain, and as easy to reach as the other one. This is a popup someone did not
                    // ask for; making the way out quieter than the way in would be the wrong kind
                    // of persuasion.
                    Button("No thanks") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(.top, Theme.Spacing.xs)
                }

                if case .failed(let message) = store.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task { await store.loadPrice() }
        .postHogScreenView("Streak Repair Offer")
    }

    private var isWorking: Bool {
        store.phase == .purchasing || store.phase == .confirming || store.phase == .loadingPrice
    }

    private var title: String {
        if case .repaired(let restored) = store.phase {
            return "Your \(restored)-day streak is back"
        }
        return "Your \(streak)-day streak ended"
    }

    private var subtitle: String {
        switch store.phase {
        case .repaired:
            return "Answer today's question together to keep it going."
        case .confirming:
            return "Just finishing up…"
        default:
            // States the fact and the remedy. Deliberately does not say how long they have — a
            // deadline on this screen would be pressure, and the offer expiring quietly is kinder
            // than a countdown.
            return "You missed yesterday. You can bring the streak back and carry on where you left off."
        }
    }

    /// True when the couple's included monthly repair is still unspent — in which case this popup
    /// is not an offer to buy anything.
    private var hasFreeze: Bool { appModel.streakRepair?.monthlyFreezeAvailable == true }

    private var primaryTitle: String {
        if isWorking { return "One moment…" }
        // No price on the button when the repair is included. Naming one, or even saying "bring it
        // back" next to a price elsewhere, would be asking somebody to pay for something their plan
        // already covers — which is worse than never offering it.
        if hasFreeze { return "Use this month's repair" }
        return store.displayPrice.map { "Bring it back — \($0)" } ?? "Bring it back"
    }

    /// Three routes, in order of what it would be wrong to skip.
    ///
    /// The included monthly repair first: a Premium couple has already paid for this, and charging
    /// them again because the popup only knew how to sell is the one outcome worth writing code to
    /// prevent. Then a credit they are already holding — they paid, the app closed, the webhook
    /// landed since, and there is nothing left to buy. Only then a purchase.
    private func repairNow() async {
        let repaired: Bool
        if hasFreeze {
            repaired = await store.useMonthlyFreeze()
        } else if (appModel.streakRepair?.credits ?? 0) > 0 {
            repaired = await store.spendCredit()
        } else {
            repaired = await store.purchaseAndRepair()
        }
        if repaired {
            await appModel.refreshDailyStreak()
            await appModel.refreshStreakRepairState()
        }
    }
}
