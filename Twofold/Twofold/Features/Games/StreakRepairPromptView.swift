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

    private var primaryTitle: String {
        if isWorking { return "One moment…" }
        return store.displayPrice.map { "Bring it back — \($0)" } ?? "Bring it back"
    }

    /// Someone may already hold a credit — they paid, the app closed, the webhook landed since. In
    /// that case there is nothing to buy and this should just spend it.
    private func repairNow() async {
        let repaired = (appModel.streakRepair?.credits ?? 0) > 0
            ? await store.spendCredit()
            : await store.purchaseAndRepair()
        if repaired { await appModel.refreshDailyStreak() }
    }
}
