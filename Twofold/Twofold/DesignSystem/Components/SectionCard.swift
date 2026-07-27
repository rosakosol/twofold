//
//  SectionCard.swift
//  Twofold
//

import SwiftUI

/// Rounded white card container used across the Globe, Trips, and Stats screens.
struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content
        }
        .padding(Theme.Spacing.md)
        // `Theme.cardBackground` is a flat system color with no elevation/shadow of its own —
        // against dark mode's now-deep `Theme.backgroundGradient`, a stack of these otherwise
        // read as one undifferentiated slab of dark gray with no visible seams between cards. In
        // dark mode a translucent `Theme.cardGradientDark` wash on top lifts the card a shade
        // brighter than the page instead; light mode keeps the plain fill + hairline border,
        // which already reads clearly against its own pale background.
        .background {
            ZStack {
                Theme.cardBackground
                if colorScheme == .dark {
                    Theme.cardGradientDark
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            if colorScheme != .dark {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.subtleInk.opacity(0.18), lineWidth: 1)
            }
        }
    }
}
