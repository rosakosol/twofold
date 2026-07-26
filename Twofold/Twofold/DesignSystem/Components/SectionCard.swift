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
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        // `Theme.cardBackground` is a flat system color with no elevation/shadow of its own —
        // against dark mode's now-deep `Theme.backgroundGradient`, a stack of these otherwise
        // read as one undifferentiated slab of dark gray with no visible seams between cards. A
        // light-on-dark border reads clearly there; a plain `Theme.subtleInk` tint at the same
        // strength would have been too washed out to actually notice, so this is a deliberate
        // colorScheme split rather than one shared adaptive color.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.22) : Theme.subtleInk.opacity(0.18),
                    lineWidth: colorScheme == .dark ? 1.25 : 1
                )
        )
    }
}
