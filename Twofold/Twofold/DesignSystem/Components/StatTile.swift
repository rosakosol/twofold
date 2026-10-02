//
//  StatTile.swift
//  Twofold
//

import SwiftUI

/// The stat tile of the redesign (docs/TWOFOLD_DESIGN.md, section 5): a card with a 36pt rounded-
/// square chip filled with one of five gradients, a 12pt `textSecondary` label, a 20pt bold value
/// and an optional sub-label.
///
/// Two layouts. `row` (chip beside the text) is for the Stats grids, where tiles sit two abreast.
/// `stacked` (chip above, centred) is for a short line of tiles across a screen, as onboarding
/// uses it.
struct StatTile: View {
    /// The chip's gradient. White icon on each clears 4.5:1.
    enum Chip {
        case blue, green, indigo, coral, violet

        var gradient: LinearGradient {
            switch self {
            case .blue: Brand.gradient(0x1A6FD6, 0x0B5FB0)
            case .green: Brand.greenGradient
            case .indigo: Brand.indigoGradient
            case .coral: Brand.coralGradient
            case .violet: Brand.violet
            }
        }
    }

    enum Layout { case row, stacked }

    let icon: String
    let label: String
    let value: String
    var detail: String?
    var chip: Chip = .blue
    var layout: Layout = .row

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tiles in a grid line up only if every one is the same height, which the one-line caps buy.
    /// At accessibility sizes the grid becomes a single column with no neighbour to match, so the
    /// caps come off and the text wraps and grows instead.
    private var capsLines: Bool { !dynamicTypeSize.isAccessibilitySize }

    /// The Stats grid's form: chip beside label, value and sub-label.
    init(icon: String, label: String, value: String, detail: String? = nil, chip: Chip = .blue) {
        self.icon = icon
        self.label = label
        self.value = value
        self.detail = detail
        self.chip = chip
        self.layout = .row
    }

    /// The stacked form: chip above value above label, centred.
    init(icon: String, value: String, label: String, chip: Chip = .blue) {
        self.icon = icon
        self.label = label
        self.value = value
        self.detail = nil
        self.chip = chip
        self.layout = .stacked
    }

    var body: some View {
        Group {
            switch layout {
            case .row: rowBody
            case .stacked: stackedBody
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chipView: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onFill)
            .frame(width: 36, height: 36)
            .background(chip.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private var rowBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            chipView
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(capsLines ? 1 : nil)
                    .minimumScaleFactor(capsLines ? 0.75 : 1)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(capsLines ? 1 : nil)
                    .minimumScaleFactor(capsLines ? 0.7 : 1)
                // Reserved even when empty, so a tile without a sub-label is as tall as its
                // neighbour with one.
                Text(detail ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(capsLines ? 1 : nil)
                    .opacity(detail == nil ? 0 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm + 4)
        .themedCardBackground(cornerRadius: Theme.Radius.tile)
    }

    private var stackedBody: some View {
        VStack(spacing: Theme.Spacing.sm) {
            chipView
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        HStack {
            StatTile(icon: "heart.fill", label: "Total reunions", value: "9", chip: .coral)
            StatTile(icon: "airplane", label: "Furthest apart", value: "16,021 km", chip: .blue)
        }
        HStack {
            StatTile(icon: "globe", value: "4", label: "Countries", chip: .green)
            StatTile(icon: "heart.fill", value: "127", label: "Days together", chip: .coral)
        }
    }
    .padding()
    .background(Theme.backgroundGradient)
}
