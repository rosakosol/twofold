//
//  PillBadge.swift
//  Twofold
//

import SwiftUI

struct PillBadge: View {
    let text: String
    var tint: Color = Theme.leafGreen
    /// True for pure category/label pills with no real state behind them (a game topic, a game
    /// type tag) — Aurora rule #2 says a hue means state (blue = live, green = matched, red =
    /// destructive/love) and never appears decoratively, so these get the neutral chip treatment
    /// in dark mode instead of carrying their own decorative color. Light mode is untouched
    /// either way — this only ever changes the dark-mode rendering.
    var isNeutral: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkNeutral: Bool { isNeutral && colorScheme == .dark }
    private var textColor: Color { isDarkNeutral ? Theme.subtleInk : tint }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .foregroundStyle(textColor)
            .background(isDarkNeutral ? TwofoldDark.Accent.neutralChip : tint.opacity(0.15), in: Capsule())
            .overlay {
                // Aurora chips carry a hairline edge alongside the fill — light mode's flat fill
                // with no border is left exactly as it was.
                if colorScheme == .dark {
                    Capsule().stroke(isDarkNeutral ? TwofoldDark.Line.strong : tint.opacity(0.34), lineWidth: 1)
                }
            }
    }
}
