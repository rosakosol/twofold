//
//  StatsCardComponents.swift
//  Twofold
//
//  The pieces both full-stats screens are built from — All Flight Stats (`FullStatsView`) and All
//  Trip Stats (`FullTripStatsView`). They were private to the flight screen; the trip one needs the
//  same card chrome, and two copies of it would drift the moment either changed.
//

import SwiftUI

/// A stat card's icon, title and headline figure.
struct StatCardHeader: View {
    let icon: String
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().fill(Theme.skyBlueText.opacity(0.15))
                    Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.skyBlueText)
                }
                .frame(width: 32, height: 32)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            Text("\(Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlueText))\(Text(unit.map { " \($0)" } ?? "").font(.title3.weight(.semibold)).foregroundStyle(Theme.subtleInk))")
        }
    }
}

/// One label-and-figure line inside a stat card.
struct StatBreakdownRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }
}

/// A ranked list with a way to reach the rest of it.
///
/// The "Show all N" affordance exists because a card headlining a count of everything while listing
/// only its top few reads as a number that can't be right — reported exactly that way on the flight
/// screen, where "22" sat above three airports.
struct StatRankedRows: View {
    struct Entry: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let title: String
    let ranked: [Entry]
    /// Shared across a screen's cards so each remembers its own state independently, keyed by title.
    @Binding var expanded: Set<String>
    /// 3 on most cards, 5 for countries — those lists were already different lengths and there's no
    /// reason to flatten them.
    var collapsedLimit: Int = 3

    private var isExpanded: Bool { expanded.contains(title) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(ranked.prefix(isExpanded ? ranked.count : collapsedLimit)) { entry in
                StatBreakdownRow(label: entry.name, value: "×\(entry.count)")
            }
            if ranked.count > collapsedLimit {
                Button(isExpanded ? "Show less" : "Show all \(ranked.count)") {
                    withAnimation {
                        if isExpanded { expanded.remove(title) } else { expanded.insert(title) }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.skyBlueText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
