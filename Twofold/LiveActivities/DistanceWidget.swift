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
    let isSameCity: Bool
    let myCity: String?
    let partnerCity: String?
    let myName: String
    let partnerName: String
}

struct DistanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DistanceEntry {
        DistanceEntry(date: .now, distanceLabel: "6,060 km", isSameCity: false, myCity: "Melbourne", partnerCity: "Singapore", myName: "You", partnerName: "Partner")
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
            isSameCity: snapshot?.isSameCity ?? false,
            myCity: snapshot?.myCity,
            partnerCity: snapshot?.partnerCity,
            myName: snapshot?.myName ?? "You",
            partnerName: snapshot?.partnerName ?? "Partner"
        )
    }
}

struct DistanceWidgetView: View {
    let entry: DistanceEntry

    @Environment(\.widgetFamily) private var family

    /// Big, non-overlapping circles either side of a heart — deliberately not the small
    /// overlapping-avatar pairing `DistanceCompactWidget` uses; this is the whole content of the
    /// widget's top row, not a compact accessory to some other primary element.
    private var bigPairWithHeart: some View {
        HStack(spacing: 6) {
            PersonInitialBadge(letter: personInitial(entry.myName), size: 28)
            Image(systemName: "heart.fill")
                .font(.system(size: 11))
            PersonInitialBadge(letter: personInitial(entry.partnerName), size: 28)
        }
    }

    /// Distinguishes three states, not two: cities never set at all ("Add your home cities"),
    /// set but identical ("We're together!" — `entry.isSameCity`, not just a near-zero distance),
    /// and set with a real distance between them. `distanceLabel` alone can't tell the first two
    /// apart — `WidgetSnapshotWriter` deliberately leaves it nil for a same-city couple too.
    @ViewBuilder
    private var distanceOrTogetherText: some View {
        if entry.myCity == nil || entry.partnerCity == nil {
            Text("Add your home cities")
        } else if entry.isSameCity {
            Text("We're together!")
        } else if let distanceLabel = entry.distanceLabel {
            Text(distanceLabel)
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: accessoryInline
            default: accessoryRectangular
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    private var accessoryRectangular: some View {
        VStack(spacing: 2) {
            bigPairWithHeart
            distanceOrTogetherText
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// The Lock Screen's single text-line slot — no room for the initial badges, just the
    /// distance/together text itself.
    @ViewBuilder
    private var accessoryInline: some View {
        if entry.myCity == nil || entry.partnerCity == nil {
            Label("Add your home cities", systemImage: "arrow.left.and.right")
        } else if entry.isSameCity {
            Label("We're together!", systemImage: "heart.fill")
        } else if let distanceLabel = entry.distanceLabel {
            Label("\(distanceLabel) apart", systemImage: "arrow.left.and.right")
        }
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
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .accessoryRectangular) {
    DistanceWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: "6,060 km", isSameCity: false, myCity: "Melbourne", partnerCity: "Singapore", myName: "Rosa", partnerName: "Dara")
}

#Preview(as: .accessoryInline) {
    DistanceWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: "6,060 km", isSameCity: false, myCity: "Melbourne", partnerCity: "Singapore", myName: "Rosa", partnerName: "Dara")
}

#Preview("Same city", as: .accessoryRectangular) {
    DistanceWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: nil, isSameCity: true, myCity: "Melbourne", partnerCity: "Melbourne", myName: "Rosa", partnerName: "Dara")
}
