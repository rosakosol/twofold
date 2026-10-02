//
//  StatsHeroCard.swift
//  Twofold
//

import SwiftUI

/// The summary card at the top of a Stats section (docs/TWOFOLD_DESIGN.md, section 6): a coloured
/// gradient with the top-right highlight, white text, and the section's share button in the corner.
/// `heroBlue` for the relationship, `heroBlueGreen` for trips, `flight` for flights.
struct StatsHeroCard<Content: View>: View {
    let gradient: LinearGradient
    var shareLabel: String?
    var onShare: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            content
        }
        .foregroundStyle(Theme.onFill)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if let onShare, let shareLabel {
                StatsShareButton(label: shareLabel, action: onShare)
                    .padding(Theme.Spacing.sm)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(gradient)
                .overlay { BrandHighlight() }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, y: Theme.Shadow.y)
    }
}

/// One of the numbers across a hero card: a 12pt label over a bold value, both white.
struct StatsHeroNumber: View {
    let label: String
    let value: String
    var capsLines: Bool = true
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
                .lineLimit(capsLines ? 1 : nil)
                .minimumScaleFactor(capsLines ? 0.8 : 1)
            Text(value)
                .font(.system(size: valueSize, weight: .bold))
                .lineLimit(capsLines ? 1 : nil)
                .minimumScaleFactor(capsLines ? 0.6 : 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
