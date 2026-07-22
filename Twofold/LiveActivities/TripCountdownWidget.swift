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
}

struct TripCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripCountdownEntry {
        TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
    }

    func getSnapshot(in context: Context, completion: @escaping (TripCountdownEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripCountdownEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> TripCountdownEntry {
        guard let reunion = snapshot?.nextReunion else {
            return TripCountdownEntry(date: .now, daysToGo: nil, destinationCity: nil)
        }
        let days = Calendar.current.dateComponents([.day], from: .now, to: reunion.departureDate).day ?? 0
        return TripCountdownEntry(date: .now, daysToGo: max(0, days), destinationCity: reunion.destinationCity)
    }
}

struct TripCountdownWidgetView: View {
    let entry: TripCountdownEntry

    @Environment(\.widgetFamily) private var family

    private var caption: String {
        guard entry.daysToGo != nil else { return "No trip planned yet" }
        return entry.destinationCity.map { "until you're in \($0)" } ?? "until your reunion"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: accessoryCircular
            case .accessoryRectangular: accessoryRectangular
            case .accessoryInline: accessoryInline
            default: homeScreenBody
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Trip Countdown", systemImage: "heart.fill")
                .font(.caption2.weight(.bold))
            Spacer()
            Text(entry.daysToGo.map { $0 == 0 ? "🎉" : "\($0)" } ?? "✈️")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "FF6B81"), Color(hex: "C93756")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 60))
                .opacity(0.18)
                .foregroundStyle(.white)
                .offset(x: 16, y: 16)
        }
        .widgetBranded()
    }

    @ViewBuilder
    private var accessoryRectangular: some View {
        if let daysToGo = entry.daysToGo {
            VStack(alignment: .leading, spacing: 1) {
                Label(daysToGo == 0 ? "Today" : "\(daysToGo) days", systemImage: "heart.fill")
                    .font(.headline)
                Text(caption)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Label("No trip planned yet", systemImage: "heart.fill")
        }
    }

    /// The Lock Screen's single text-line slot — same "Today"/celebratory-glyph treatment as
    /// the other accessory families.
    @ViewBuilder
    private var accessoryInline: some View {
        if let daysToGo = entry.daysToGo {
            if daysToGo == 0 {
                Label("Trip day is today! 🎉", systemImage: "heart.fill")
            } else {
                Label(entry.destinationCity.map { "\(daysToGo)d until \($0)" } ?? "\(daysToGo) days until your trip", systemImage: "heart.fill")
            }
        } else {
            Label("No trip planned yet", systemImage: "heart.fill")
        }
    }

    /// Small Lock Screen slot — condensed to the number + a one-word label, same treatment as
    /// DaysTogetherWidget's own `accessoryCircular`. `daysToGo == 0` gets a small celebratory
    /// glyph instead of "0 / days", since "today" doesn't read as a countdown anymore.
    @ViewBuilder
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let daysToGo = entry.daysToGo {
                if daysToGo == 0 {
                    Text("🎉").font(.title2)
                } else {
                    VStack(spacing: 0) {
                        Text("\(daysToGo)").font(.system(.title3, design: .rounded).bold())
                        Text("to go").font(.caption2)
                    }
                }
            } else {
                Image(systemName: "heart.fill")
            }
        }
    }
}

struct TripCountdownWidget: Widget {
    // Deliberately unchanged from before this file's own rename — see the file header.
    let kind = "NextReunionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripCountdownProvider()) { entry in
            TripCountdownWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Trip Countdown")
        .description("Countdown to your next trip together, on your Home or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}

#Preview(as: .accessoryRectangular) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}

#Preview(as: .accessoryCircular) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}

#Preview(as: .accessoryInline) {
    TripCountdownWidget()
} timeline: {
    TripCountdownEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}
