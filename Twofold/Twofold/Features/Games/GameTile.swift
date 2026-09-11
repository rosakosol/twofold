//
//  GameTile.swift
//  Twofold
//
//  A game, in one compact row, for the Games hub's two lists.
//
//  `GameCard` is the big square one: 170pt tall, an icon over a centred title, and the right thing
//  for the Globe homepage's recommended row, where two or three cards are the whole point of the
//  section. Nine of them on one screen is something else — the hub was over 700pt of cards before
//  anything else on it, and the last game sat below two scrolls of nothing but names.
//
//  This is the same information at a third of the height: icon beside the name rather than above
//  it, which also handles "Who's More Likely To" and "Sudoku" in the same grid without either one
//  looking wrong.
//

import SwiftUI

struct GameTile: View {
    let gameType: GameType
    /// Dimmed with a lock rather than hidden, so someone who has not connected a partner still sees
    /// what is waiting for them — the same reasoning `GameCard` uses.
    var isLocked: Bool = false

    /// The game type's own accent, on the icon only. The tile surface stays neutral: a game type is
    /// not a blue/green/red *state*, so per Aurora rule #2 it gets one coloured accent rather than
    /// a coloured wash.
    private var accentColor: Color { gameType.iconGradient.first ?? Theme.skyBlue }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: gameType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isLocked ? Theme.subtleInk : accentColor)
                .frame(width: 26)

            Text(gameType.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                // The longest name is nearly three times the shortest, and a tile that truncated
                // "Who's More Likely To" would be hiding the only part that says what it is.
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .opacity(isLocked ? 0.62 : 1)
        .themedCardBackground(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLocked ? "Requires a partner" : "")
    }
}

#Preview {
    ScrollView {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm),
                      GridItem(.flexible(), spacing: Theme.Spacing.sm)],
            spacing: Theme.Spacing.sm
        ) {
            ForEach(GameType.allCases) { gameType in
                GameTile(gameType: gameType, isLocked: gameType == .chess)
            }
        }
        .padding()
    }
    .background(Theme.backgroundGradient)
}
