//
//  WidgetsCatalogView.swift
//  Twofold
//
//  Lists what's available and how to add it — there's no public API to deep-link directly into
//  the system widget gallery pre-filtered to one app, so "long-press your Home Screen" is the
//  standard instruction every app gives here. Preview art/live rendering arrives once the real
//  widgets are built; this is the navigable placeholder for that.
//

import PostHog
import SwiftUI

private struct WidgetCatalogEntry: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let systemImage: String
    /// "plus"/"premium" — matches WidgetTier/AppModel.subscriptionTier's tier strings.
    let tier: String
}

struct WidgetsCatalogView: View {
    @Environment(AppModel.self) private var appModel

    private let entries: [WidgetCatalogEntry] = [
        WidgetCatalogEntry(name: "Reunion & Trip Countdown", subtitle: "Time until you're together, or until takeoff", systemImage: "airplane.departure", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Flight Status", subtitle: "Live status, route, and estimated time, for your next flight", systemImage: "airplane.circle.fill", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Anniversary", subtitle: "Your running days-together total", systemImage: "heart.fill", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Partner's Time", subtitle: "Their local time, at a glance", systemImage: "clock.fill", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Time & Weather", subtitle: "Their time and forecast, side by side", systemImage: "cloud.sun.fill", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Drawing Pad", subtitle: "Whatever's currently drawn, with a nudge button", systemImage: "pencil.tip", tier: WidgetTier.plus),
        WidgetCatalogEntry(name: "Smart Rotating", subtitle: "Cycles through your other widgets automatically", systemImage: "arrow.triangle.2.circlepath", tier: WidgetTier.premium),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Long-press your Home Screen, tap +, then search “Twofold” to add any of these.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                        Text("Small widgets also work on your Lock Screen — long-press the Lock Screen, tap Customize.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }

                ForEach(entries) { entry in
                    SectionCard {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: entry.systemImage)
                                .font(.title3)
                                .foregroundStyle(Theme.ink)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(.subheadline.weight(.semibold))
                                Text(entry.subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
                            }

                            Spacer()

                            tierBadge(for: entry.tier)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Widgets Catalog")
    }

    @ViewBuilder
    private func tierBadge(for requiredTier: String) -> some View {
        let isLocked = WidgetTier.isLocked(required: requiredTier, current: appModel.subscriptionTier)
        if isLocked {
            PillBadge(text: "Locked", tint: Theme.subtleInk)
        } else if requiredTier == WidgetTier.premium {
            PillBadge(text: "Premium", tint: Theme.skyBlue)
        } else {
            PillBadge(text: "Plus", tint: Theme.leafGreen)
        }
    }
}

#Preview {
    NavigationStack {
        WidgetsCatalogView()
    }
    .environment(AppModel())
}
