//
//  DistanceWidget.swift
//  LiveActivities
//
//  Basic tier (free) — one of the app's three Lock Screen widgets (Distance, Days Together,
//  Next Reunion), each Lock Screen–only and full-width (.accessoryRectangular). `distanceLabel`
//  arrives pre-formatted from WidgetSnapshotWriter (see WidgetSnapshot.swift's doc comment) since
//  MeasurementPreference reads UserDefaults.standard, which this extension's process doesn't share
//  with the host app.
//

import SwiftUI
import WidgetKit

struct DistanceEntry: TimelineEntry {
    let date: Date
    let distanceLabel: String?
    let myCity: String?
    let partnerCity: String?
}

struct DistanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DistanceEntry {
        DistanceEntry(date: .now, distanceLabel: "6,060 km", myCity: "Melbourne", partnerCity: "Singapore")
    }

    func getSnapshot(in context: Context, completion: @escaping (DistanceEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DistanceEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        // Distance only changes when someone updates a home city — a rare, WidgetSnapshotWriter
        // .refresh()-triggered event, not something worth polling for. A daily refresh (same
        // cadence as DaysTogetherWidget) is just a safety net against a missed reload.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> DistanceEntry {
        DistanceEntry(date: .now, distanceLabel: snapshot?.distanceLabel, myCity: snapshot?.myCity, partnerCity: snapshot?.partnerCity)
    }
}

struct DistanceWidgetView: View {
    let entry: DistanceEntry

    var body: some View {
        Group {
            if let distanceLabel = entry.distanceLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Label(distanceLabel, systemImage: "figure.2.arms.open")
                        .font(.headline)
                    if let myCity = entry.myCity, let partnerCity = entry.partnerCity {
                        Text("\(myCity) ↔ \(partnerCity)")
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Label("Add your home cities", systemImage: "figure.2.arms.open")
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }
}

struct DistanceWidget: Widget {
    let kind = "DistanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DistanceProvider()) { entry in
            DistanceWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Distance Apart")
        .description("How far apart you and your partner are right now, on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .accessoryRectangular) {
    DistanceWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: "6,060 km", myCity: "Melbourne", partnerCity: "Singapore")
}
