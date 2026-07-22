//
//  NextReunionWidget.swift
//  LiveActivities
//
//  Basic tier (free) — one of the app's Lock Screen widgets (Distance, Days Together, Next
//  Reunion), Lock Screen–only, available both full-width (.accessoryRectangular) and as a small
//  circle (.accessoryCircular). Counts down the soonest upcoming *trip* (WidgetSnapshot.nextReunion,
//  sourced from AppModel.upcomingTrips.first — the same trip Home's "next reunion" card and
//  nextReunionDaysToGo use), not a tracked flight — a trip's own departure date is what marks
//  "when we'll be together", and not every trip has an AeroAPI-tracked flight attached (that's
//  TripCountdownWidget's separate, flight-specific concern).
//

import SwiftUI
import WidgetKit

struct NextReunionEntry: TimelineEntry {
    let date: Date
    let daysToGo: Int?
    let destinationCity: String?
}

struct NextReunionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextReunionEntry {
        NextReunionEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
    }

    func getSnapshot(in context: Context, completion: @escaping (NextReunionEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextReunionEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> NextReunionEntry {
        guard let reunion = snapshot?.nextReunion else {
            return NextReunionEntry(date: .now, daysToGo: nil, destinationCity: nil)
        }
        let days = Calendar.current.dateComponents([.day], from: .now, to: reunion.departureDate).day ?? 0
        return NextReunionEntry(date: .now, daysToGo: max(0, days), destinationCity: reunion.destinationCity)
    }
}

struct NextReunionWidgetView: View {
    let entry: NextReunionEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: accessoryCircular
            default: accessoryRectangular
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    @ViewBuilder
    private var accessoryRectangular: some View {
        if let daysToGo = entry.daysToGo {
            VStack(alignment: .leading, spacing: 1) {
                Label(daysToGo == 0 ? "Today" : "\(daysToGo) days", systemImage: "heart.fill")
                    .font(.headline)
                Text(entry.destinationCity.map { "until you're in \($0)" } ?? "until your reunion")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

struct NextReunionWidget: Widget {
    let kind = "NextReunionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextReunionProvider()) { entry in
            NextReunionWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Reunion")
        .description("Countdown to when you'll next be together, on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .accessoryRectangular) {
    NextReunionWidget()
} timeline: {
    NextReunionEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}

#Preview(as: .accessoryCircular) {
    NextReunionWidget()
} timeline: {
    NextReunionEntry(date: .now, daysToGo: 12, destinationCity: "Singapore")
}
