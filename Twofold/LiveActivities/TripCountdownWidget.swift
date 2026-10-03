//
//  TripCountdownWidget.swift
//  LiveActivities
//
//  Basic tier (free) — was "NextReunionWidget" (display name only; this was already, functionally,
//  the real trip countdown: counts down the soonest upcoming *trip* (WidgetSnapshot.nextReunion,
//  sourced from AppModel.upcomingTrips.first — the same trip Home's "next reunion" card and
//  nextReunionDaysToGo use), not a tracked flight — a trip's own departure date is what marks
//  "when we'll be together", and not every trip has an AeroAPI-tracked flight attached (that's
//  FlightCountdownWidget's separate, flight-specific — and user-configurable — concern). `kind`
//  stays "NextReunionWidget" to avoid orphaning already-placed Lock Screen instances.
//
//  Available on the Lock Screen (.accessoryRectangular/.accessoryCircular, as before) and now
//  also the Home Screen (.systemSmall).
//

import SwiftUI
import WidgetKit

struct TripCountdownEntry: TimelineEntry {
    let date: Date
    let daysToGo: Int?
    let destinationCity: String?
    /// Which trip this is counting down to, so tapping opens it. Nil for a snapshot written before
    /// `ReunionInfo` carried an id, and for the placeholder.
    let tripID: UUID?
    var isReunionTrip: Bool = true
    var untilPhrase: String? = nil
}

struct TripCountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TripCountdownEntry {
        TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore", tripID: nil)
    }

    func snapshot(for configuration: SelectTripIntent, in context: Context) async -> TripCountdownEntry {
        entry(for: configuration, from: WidgetSnapshot.read())
    }

    func timeline(for configuration: SelectTripIntent, in context: Context) async -> Timeline<TripCountdownEntry> {
        let current = entry(for: configuration, from: WidgetSnapshot.read())
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        return Timeline(entries: [current], policy: .after(midnight))
    }

    /// Which trip this instance counts down to: the picked one while it's still upcoming,
    /// otherwise the soonest. So an unconfigured widget — or one whose trip has since been taken
    /// or deleted — degrades to exactly the behaviour this widget had before it was configurable,
    /// rather than going blank. Same resolution `FlightCountdownProvider` uses.
    private func selectedTrip(for configuration: SelectTripIntent, snapshot: WidgetSnapshot?) -> WidgetSnapshot.ReunionInfo? {
        let upcoming = snapshot?.upcomingTrips ?? []
        if let selectedID = configuration.trip?.id, let match = upcoming.first(where: { $0.id == selectedID }) {
            return match
        }
        return upcoming.first ?? snapshot?.nextReunion
    }

    private func entry(for configuration: SelectTripIntent, from snapshot: WidgetSnapshot?) -> TripCountdownEntry {
        guard let reunion = selectedTrip(for: configuration, snapshot: snapshot) else {
            return TripCountdownEntry(date: .now, daysToGo: nil, destinationCity: nil, tripID: nil)
        }
        let days = TimeMath.daysUntil(reunion.departureDate)
        return TripCountdownEntry(
            date: .now, daysToGo: max(0, days), destinationCity: reunion.destinationCity, tripID: reunion.id,
            isReunionTrip: reunion.isReunionTrip, untilPhrase: reunion.untilPhrase
        )
    }
}

struct TripCountdownWidgetView: View {
    let entry: TripCountdownEntry
    @Environment(\.widgetFamily) private var family

    /// "until Alex lands in Melbourne" (section 7), falling back to the city alone for a snapshot
    /// written before the app knew who was travelling.
    private var caption: String {
        guard entry.daysToGo != nil else { return "No trip planned yet" }
        return entry.untilPhrase ?? entry.destinationCity.map { "until you're in \($0)" } ?? "until you're together"
    }

    private var countLabel: String {
        guard let days = entry.daysToGo else { return "" }
        if days == 0 { return "Today" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: accessoryCircular.accessoryContainer()
            case .accessoryRectangular: accessoryRectangular.accessoryContainer()
            case .accessoryInline: accessoryInline.accessoryContainer()
            default: homeScreenBody
            }
        }
        .widgetURL(entry.tripID.map { URL(string: "twofold://trip/\($0.uuidString)") } ?? URL(string: "twofold://home"))
    }

    /// Coral, white text (section 7): "Next reunion", "22 days", "until Alex lands in Melbourne".
    @ViewBuilder
    private var homeScreenBody: some View {
        if entry.daysToGo != nil {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isReunionTrip ? "Next reunion" : "Next trip")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.92)
                Spacer(minLength: 0)
                Text(countLabel)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(caption)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.92)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .widgetSurface(Brand.coralGradient)
        } else {
            WidgetEmptyState(systemImage: "heart.fill", message: "No trip planned yet", gradient: Brand.coralGradient)
        }
    }

    private var accessoryRectangular: some View {
        Group {
            if entry.daysToGo != nil {
                VStack(alignment: .leading, spacing: 1) {
                    Label(countLabel, systemImage: "heart.fill")
                        .font(.headline)
                        .widgetAccentable()
                    Text(caption)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Label("No trip planned yet", systemImage: "heart.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessoryContainer()
    }

    private var accessoryInline: some View {
        Group {
            if let daysToGo = entry.daysToGo {
                if daysToGo == 0 {
                    Label("Trip day is today", systemImage: "heart.fill")
                } else {
                    Label(entry.destinationCity.map { "\(daysToGo)d until \($0)" } ?? "\(daysToGo) days until your trip", systemImage: "heart.fill")
                }
            } else {
                Label("No trip planned yet", systemImage: "heart.fill")
            }
        }
        .accessoryContainer()
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let daysToGo = entry.daysToGo {
                if daysToGo == 0 {
                    Image(systemName: "heart.fill").font(.title3).widgetAccentable()
                } else {
                    VStack(spacing: 0) {
                        Text("\(daysToGo)").font(.title3.bold()).widgetAccentable()
                        Text("to go").font(.caption2)
                    }
                }
            } else {
                Image(systemName: "heart.fill")
            }
        }
        .accessoryContainer()
    }
}

struct TripCountdownWidget: Widget {
    // Deliberately unchanged from before this file's own rename — see the file header.
    let kind = "NextReunionWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectTripIntent.self, provider: TripCountdownProvider()) { entry in
            TripCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Trip Countdown")
        .description("Countdown to your chosen trip together.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore", tripID: nil)
}

#Preview(as: .accessoryRectangular) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore", tripID: nil)
}

#Preview(as: .accessoryCircular) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore", tripID: nil)
}

#Preview(as: .accessoryInline) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore", tripID: nil)
}
