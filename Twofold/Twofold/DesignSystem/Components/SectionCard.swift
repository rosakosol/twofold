//
//  SectionCard.swift
//  Twofold
//

import SwiftUI

/// Rounded white card container used across the Globe, Trips, and Stats screens.
struct SectionCard<Content: View>: View {
    var content: Content
    /// `false` only for cards that sit directly over their own busy blue/green content (e.g. the
    /// Memories map's "Add your first memory" hint, floating over the map itself) — the dark-mode
    /// wash below is the same blue-to-green tint as the map, so it disappeared into it instead of
    /// reading as a card. Everywhere else keeps the wash (the default).
    var appliesDarkWash: Bool = true
    /// True for the one screen-level "hero" object (Aurora rule #3 — one gradient per screen,
    /// only the primary object) — swaps the ordinary dark-mode card tint for `Surface.hero`'s
    /// gradient, `Line.hero`'s border, and the hero drop shadow. At most one card per screen
    /// should ever set this.
    var isHeroInDark: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// Explicit init (rather than relying on the synthesized memberwise one) so `content` can
    /// stay the trailing closure regardless of which of the two flags after it a call site sets —
    /// the synthesized init requires arguments in declaration order, which broke callers wanting
    /// to pass `isHeroInDark` without also spelling out `appliesDarkWash`.
    init(appliesDarkWash: Bool = true, isHeroInDark: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.appliesDarkWash = appliesDarkWash
        self.isHeroInDark = isHeroInDark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content
        }
        .padding(Theme.Spacing.md)
        // `Theme.cardBackground` is a flat system color with no elevation/shadow of its own —
        // against dark mode's now-deep `Theme.backgroundGradient`, a stack of these otherwise
        // read as one undifferentiated slab of dark gray with no visible seams between cards. In
        // dark mode `Theme.cardGradientDark` (Aurora's neutral `Surface.card` tint) lifts the
        // card a shade brighter than the page instead; light mode keeps the plain fill.
        .background {
            ZStack {
                Theme.cardBackground
                if colorScheme == .dark {
                    if isHeroInDark {
                        TwofoldDark.Surface.hero
                    } else if appliesDarkWash {
                        Theme.cardGradientDark
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        // Both appearances get a hairline now — Aurora rule #5 ("depth = three surface steps +
        // a 1px hairline") wants one in dark mode too, not just light's existing edge.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? (isHeroInDark ? TwofoldDark.Line.hero : TwofoldDark.Line.hairline)
                        : Theme.subtleInk.opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(
            color: colorScheme == .dark && isHeroInDark ? TwofoldDark.Shadow.heroColor : .clear,
            radius: colorScheme == .dark && isHeroInDark ? TwofoldDark.Shadow.heroRadius : 0,
            y: colorScheme == .dark && isHeroInDark ? TwofoldDark.Shadow.heroY : 0
        )
    }
}
