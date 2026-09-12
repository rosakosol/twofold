//
//  StreakRepairRow.swift
//  Twofold
//
//  The offer to bring a broken streak back, on the card the streak itself lives on.
//
//  There was already a popup for this — `StreakRepairPromptView`, shown once per person per break,
//  on opening the app. That is the right shape for telling somebody something they do not know yet,
//  and the wrong shape for everything after: it is shown once and never again, so a person who
//  dismissed it, or who was not looking, had no way back to the offer at all.
//
//  This is the way back. It sits under the streak on the Games hub, which is where somebody goes
//  when they wonder what happened to it.
//
//  Premium includes one repair a month, so for those couples this is not a purchase at all — which
//  is the reason the row exists in this form rather than as a second "buy" button. Being asked to
//  pay for something your plan already includes is worse than not being offered it.
//

import SwiftUI

struct StreakRepairRow: View {
    let streak: Int
    /// True when the couple's included monthly repair is still unspent. Decided by the server —
    /// see `streak_repair_state` — because the client's idea of the tier can be out of date, and a
    /// button that promised a free repair and then refused would be worse than no button.
    let freezeAvailable: Bool
    let onUseFreeze: () -> Void
    let onBuy: () -> Void

    var isWorking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.heartRed)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your \(streak)-day streak ended")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // States the fact and nothing about how long they have. A deadline here would
                    // be pressure, and the offer lapsing quietly is kinder than a countdown — the
                    // same choice the popup makes.
                    Text("You missed yesterday. Bring it back and carry on.")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: freezeAvailable ? onUseFreeze : onBuy) {
                HStack(spacing: Theme.Spacing.xs) {
                    if isWorking { ProgressView().controlSize(.small).tint(.white) }
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(isWorking)

            if freezeAvailable {
                // Said outright, because "free" is not obvious from a button and somebody who does
                // not know it is included may not press it.
                Text("Included with Premium — one a month.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var buttonTitle: String {
        if isWorking { return "One moment…" }
        return freezeAvailable ? "Use this month's repair" : "Bring it back"
    }
}

#Preview("Included with Premium") {
    StreakRepairRow(streak: 14, freezeAvailable: true, onUseFreeze: {}, onBuy: {})
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Plus — the paid route") {
    StreakRepairRow(streak: 9, freezeAvailable: false, onUseFreeze: {}, onBuy: {})
        .padding()
        .background(Theme.backgroundGradient)
}
