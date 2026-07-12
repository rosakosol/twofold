//
//  WidgetsCatalogView.swift
//  Twofold
//
//  Lists what's available and how to add it — there's no public API to deep-link directly into
//  the system widget gallery pre-filtered to one app, so "long-press your Home Screen" is the
//  standard instruction every app gives here. Preview art/live rendering arrives once the real
//  widgets are built; this is the navigable placeholder for that.
//

import SwiftUI

private struct WidgetCatalogEntry: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let systemImage: String
    let isPremium: Bool
}

struct WidgetsCatalogView: View {
    @Environment(AppModel.self) private var appModel

    private let entries: [WidgetCatalogEntry] = [
        WidgetCatalogEntry(name: "Partner's Time", subtitle: "Their local time, at a glance", systemImage: "clock.fill", isPremium: false),
        WidgetCatalogEntry(name: "Days Together", subtitle: "Your running total", systemImage: "heart.fill", isPremium: false),
        WidgetCatalogEntry(name: "Time & Weather", subtitle: "Their time and forecast, side by side", systemImage: "cloud.sun.fill", isPremium: true),
        WidgetCatalogEntry(name: "Flight Countdown", subtitle: "Time until the next flight", systemImage: "airplane.departure", isPremium: true),
        WidgetCatalogEntry(name: "Latest Memory", subtitle: "Your most recent memory photo", systemImage: "photo.fill", isPremium: true),
        WidgetCatalogEntry(name: "Doodle Pad", subtitle: "Whatever's currently drawn", systemImage: "pencil.tip", isPremium: true),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("Long-press your Home Screen, tap +, then search “Twofold” to add any of these.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
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

                            if entry.isPremium {
                                PillBadge(text: appModel.isSubscriptionActive ? "Premium" : "Locked", tint: appModel.isSubscriptionActive ? Theme.skyBlue : Theme.subtleInk)
                            } else {
                                PillBadge(text: "Basic", tint: Theme.leafGreen)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WidgetsCatalogView()
    }
    .environment(AppModel())
}
