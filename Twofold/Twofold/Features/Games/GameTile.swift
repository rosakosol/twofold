//
//  GameTile.swift
//  Twofold
//
//  A game on the Games hub's two grids.
//
//  `GameCard` is the big square one, for the Globe homepage's recommended row, where two or three
//  cards are the whole point of the section. The hub holds eight games, so its tiles are compact:
//  92pt for the conversation games, a single row for each puzzle.
//

import SwiftUI

/// A game on the Games hub (docs/TWOFOLD_DESIGN.md, section 6, Games).
///
/// Two kinds. The four conversation games are 92pt tiles in their own gradient: white icon top
/// left, name bottom left, the game's colour doing the identifying. Puzzles are neutral cards with a
/// tinted icon chip, so the conversation games read as the headline and the puzzles as the list
/// below it.
struct GameTile: View {
    let gameType: GameType
    /// Dimmed with a lock rather than hidden, so someone who has not connected a partner still sees
    /// what is waiting for them, the same reasoning `GameCard` uses.
    var isLocked: Bool = false

    var body: some View {
        Group {
            if gameType.hasDecks {
                gradientTile
            } else {
                puzzleCard
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLocked ? "Requires a partner" : "")
    }

    private var gradientTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: gameType.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(gameType.displayName)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(2)
                // The longest name is nearly three times the shortest, and a tile that truncated
                // "Who's More Likely To" would be hiding the only part that says what it is.
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onFill)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(gameType.gradient)
                .overlay { BrandHighlight() }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .opacity(isLocked ? 0.62 : 1)
        .shadow(color: Theme.Shadow.color, radius: 10, y: 6)
    }

    private var puzzleCard: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: gameType.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isLocked ? Theme.textSecondary : gameType.chipForeground)
                .frame(width: 38, height: 38)
                .background(gameType.chipTint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            Text(gameType.displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.sm + 2)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .opacity(isLocked ? 0.62 : 1)
        .themedCardBackground(cornerRadius: Theme.Radius.tile)
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
                GameTile(gameType: gameType, isLocked: gameType == .wordSearch)
            }
        }
        .padding()
    }
    .background(Theme.backgroundGradient)
}
