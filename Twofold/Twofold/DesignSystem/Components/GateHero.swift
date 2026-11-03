//
//  GateHero.swift
//  Twofold
//
//  The round medallion at the top of a gate or a "you can't do this here" screen: a tinted disc,
//  an icon, a hairline ring, and a crown when the gate is Premium.
//
//  Six screens drew their own copy of it (the flight and deck Premium gates, the partner gate, the
//  three subscription notices), and the copies had drifted: some had the ring and some didn't, and
//  all of them filled the disc with the primary *button* gradient at 18%, a control token used as
//  decoration. The disc is `accentBackground` now, the token made for a tinted accent surface.
//

import SwiftUI

struct GateHero: View {
    enum Badge {
        /// The crown: this is behind Premium.
        case premium
    }

    private enum Symbol {
        case system(String)
        case emoji(String)
    }

    private let symbol: Symbol
    private let fill: Color
    private let badge: Badge?

    /// An SF Symbol in the accent colour.
    init(systemImage: String, badge: Badge? = nil) {
        self.symbol = .system(systemImage)
        self.fill = Theme.accentBackground
        self.badge = badge
    }

    /// An emoji (a deck's own), on `fill`: a deck gate passes its game's tint.
    init(emoji: String, fill: Color = Theme.accentBackground, badge: Badge? = nil) {
        self.symbol = .emoji(emoji)
        self.fill = fill
        self.badge = badge
    }

    /// Fixed, not scaled: the medallion is a picture, and the title under it is what grows.
    private static let size: CGFloat = 96
    private static let badgeSize: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(fill)
            switch symbol {
            case let .system(name):
                Image(systemName: name)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
            case let .emoji(emoji):
                Text(emoji).font(.system(size: 44))
            }
            Circle().strokeBorder(Theme.line, lineWidth: 1)
        }
        .frame(width: Self.size, height: Self.size)
        .overlay(alignment: .bottomTrailing) {
            if badge == .premium {
                ZStack {
                    Circle().fill(Theme.primaryButtonGradient)
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.onPrimaryButton)
                }
                .frame(width: Self.badgeSize, height: Self.badgeSize)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        GateHero(systemImage: "airplane", badge: .premium)
        GateHero(emoji: "🛫", fill: GameType.triviaBattle.chipTint, badge: .premium)
        GateHero(systemImage: "person.2.fill")
    }
}
