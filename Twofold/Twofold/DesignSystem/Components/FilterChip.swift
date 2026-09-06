//
//  FilterChip.swift
//  Twofold
//
//  The label on a menu that narrows what's on screen — the Memories list's location and time
//  filters, and the period pickers on both full-stats screens.
//
//  These were three separate hand-rolled capsules that had drifted: different fonts, different
//  padding, a leading icon on some and not others, and a `chevron.down` against a
//  `chevron.up.chevron.down`. They do the same job on four screens, so they now look the same on
//  all four.
//

import SwiftUI

struct FilterChip: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption.weight(.medium))
            Image(systemName: "chevron.down")
                .font(.caption2)
                .accessibilityHidden(true)
        }
        // One row, always. A year, a city and "All locations" are all short, but an accessibility
        // text size turns any of them into two lines and the capsule grows into the row above it.
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.ink)
        .background(Theme.cardBackground, in: Capsule())
        // Takes only the width it needs, so a chip sharing a row with a segmented control leaves
        // the rest of that row to the control.
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        FilterChip(text: "All locations", icon: "mappin")
        FilterChip(text: "2026", icon: "calendar")
    }
    .padding()
}
