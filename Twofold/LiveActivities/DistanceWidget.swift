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
    let myName: String
    let partnerName: String
}

struct DistanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DistanceEntry {
        DistanceEntry(date: .now, distanceLabel: "6,060 km", myCity: "Melbourne", partnerCity: "Singapore", myName: "You", partnerName: "Partner")
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
        DistanceEntry(
            date: .now,
            distanceLabel: snapshot?.distanceLabel,
            myCity: snapshot?.myCity,
            partnerCity: snapshot?.partnerCity,
            myName: snapshot?.myName ?? "You",
            partnerName: snapshot?.partnerName ?? "Partner"
        )
    }
}

struct DistanceWidgetView: View {
    let entry: DistanceEntry

    private func initial(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// Two overlapping bordered circles, each holding one person's initial — the same "you and
    /// your partner" pairing AvatarView's overlap treatment shows elsewhere in the app, just
    /// text-only. Accessory Lock Screen widgets render in a single system-applied tint
    /// (`.accessory` widget rendering mode ignores custom colors), so this reads as an outline +
    /// letter rather than anything resembling the real colored avatars.
    private var initialsPair: some View {
        HStack(spacing: -6) {
            initialBadge(initial(entry.myName))
            initialBadge(initial(entry.partnerName))
        }
    }

    private func initialBadge(_ letter: String) -> some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1)
            Text(letter).font(.system(size: 9, weight: .bold))
        }
        .frame(width: 16, height: 16)
    }

    var body: some View {
        Group {
            if let distanceLabel = entry.distanceLabel {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        initialsPair
                        Text(distanceLabel).font(.headline)
                    }
                    if let myCity = entry.myCity, let partnerCity = entry.partnerCity {
                        Text("\(myCity) ↔ \(partnerCity)")
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    initialsPair
                    Text("Add your home cities")
                }
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
    DistanceEntry(date: .now, distanceLabel: "6,060 km", myCity: "Melbourne", partnerCity: "Singapore", myName: "Rosa", partnerName: "Dara")
}
