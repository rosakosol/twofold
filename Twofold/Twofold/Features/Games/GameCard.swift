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

    /// This game type's own accent — same value `DeckCardRow` falls back to for a non-topic
    /// badge tint, used here for just the icon glyph. The card surface itself stays neutral (see
    /// `themedCardBackground`) — a game *type* isn't itself a blue/green/red state, so per Aurora
    /// rule #2 it doesn't get a colored card wash, just this one colored accent on the icon.
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
        .themedCardBackground(cornerRadius: Theme.Radius.card)
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
