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
        // Cards share Theme.cardBackground with their own container (SectionCard) — without
        // this, adjacent cards in the Recommended Games carousel had no visible boundary at all
        // and just blended into one continuous surface.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.subtleInk.opacity(0.15), lineWidth: 1)
        }
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
