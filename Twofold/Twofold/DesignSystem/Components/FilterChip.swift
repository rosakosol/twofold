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
        HStack(spacing: Theme.Spacing.xs) {
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
        .padding(.vertical, Theme.Spacing.xsm)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.surface, in: Capsule())
        // Takes only the width it needs, so a chip sharing a row with a segmented control leaves
        // the rest of that row to the control.
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A pill in a row of filters you pick from directly: Game history's game types and All decks'
/// Your turn / Answered / New.
///
/// These were two copies that had drifted apart in dark mode (one filled the selected pill with
/// the button gradient, the other with `selectedTab` and an accent ring), both branching on
/// `colorScheme` for what the tokens already do, and neither telling VoiceOver which was chosen.
/// Unselected, it is the chip of section 5, `raised` with a `line` edge, as on the Games hub;
/// selected, it takes the primary button's gradient, in both appearances.
struct SelectableChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                // Inside a horizontal ScrollView an unpinned label wraps rather than letting the
                // row scroll, which collapses to one letter per line at accessibility sizes.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .frame(minHeight: Theme.Control.chipHeight)
                .foregroundStyle(isSelected ? Theme.onPrimaryButton : Theme.textPrimary)
                .background(
                    isSelected ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.raised),
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule().strokeBorder(Theme.line, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack {
        HStack {
            FilterChip(text: "All locations", icon: "mappin")
            FilterChip(text: "2026", icon: "calendar")
        }
        HStack {
            SelectableChip(label: "All", isSelected: true) {}
            SelectableChip(label: "Sudoku", isSelected: false) {}
        }
    }
    .padding()
}
