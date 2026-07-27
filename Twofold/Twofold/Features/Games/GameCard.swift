//
//  GameCard.swift
//  Twofold
//
//  Shared card used both by the Globe homepage's recommended-games row and the Games hub.
//

import SwiftUI

struct GameCard: View {
    let gameType: GameType
    /// Fixed width for the Globe homepage's horizontal-scroll row; `nil` fills the available
    /// width, used by the hub's vertical sections.
    var width: CGFloat?
    /// Every game needs a partner to actually play with — dimmed with a lock badge rather than
    /// hidden or blurred outright, so someone who hasn't connected yet still gets a readable
    /// tease/preview of what's waiting for them once they do.
    var isLocked: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// This game type's own accent — same value `DeckCardRow` falls back to for a non-topic
    /// badge tint, reused here for the card's dark-mode wash (see `cardBackground`).
    private var accentColor: Color { gameType.iconGradient.first ?? Theme.skyBlue }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: gameType.icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(gameType.displayName)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(width: width, height: 170, alignment: .center)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .center)
        .background { cardBackground }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        .overlay {
            if isLocked {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.black.opacity(0.4))
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            Circle().fill(.white)
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(width: 26, height: 26)
                        .padding(Theme.Spacing.sm)
                    }
                    .overlay(alignment: .bottom) {
                        Text("Partner required")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.3), in: Capsule())
                            .padding(.bottom, Theme.Spacing.sm)
                    }
            }
        }
    }

    /// Same treatment `TopicsSection`'s own rows use: flat `Theme.cardBackground` in light mode,
    /// a translucent wash of this game type's own accent color in dark mode instead of the
    /// generic blue-to-green `Theme.cardGradientDark` every other card uses. Brighter/less
    /// opaque than a first pass at this (0.4/0.16) — that read as a dark, muddy tint rather than
    /// a genuinely colored card.
    private var cardBackground: some View {
        ZStack {
            Theme.cardBackground
            if colorScheme == .dark {
                LinearGradient(
                    colors: [accentColor.opacity(0.6), accentColor.opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            ForEach(GameType.allCases) { gameType in
                GameCard(gameType: gameType)
            }
        }
        .padding()
    }
    .background(Theme.backgroundGradient)
}
