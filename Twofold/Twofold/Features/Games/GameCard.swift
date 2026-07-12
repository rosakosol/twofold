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
    /// Every game needs a partner to actually play with — blurred/dimmed with a lock message
    /// rather than hidden outright, so someone who hasn't connected yet still sees what's
    /// waiting for them once they do.
    var isLocked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: gameType.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                PillBadge(
                    text: gameType.category.rawValue,
                    tint: gameType.category == .compete ? Theme.heartRed : Theme.skyBlue
                )

                Spacer(minLength: 0)
            }

            Text(gameType.displayName)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(gameType.tagline)
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Label(gameType.durationLabel, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                Spacer()
                Text(gameType.ctaTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.skyBlue)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: width, height: 170, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .blur(radius: isLocked ? 4 : 0)
        .overlay {
            if isLocked {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.black.opacity(0.35))
                    .overlay {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                            Text("Locked until your partner joins")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.md)
                        }
                    }
            }
        }
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(GameType.allCases) { gameType in
                GameCard(gameType: gameType, width: 220)
            }
        }
        .padding()
    }
    .background(Theme.backgroundGradient)
}
