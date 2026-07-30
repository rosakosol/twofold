//
//  DistanceCompactWidget.swift
//  LiveActivities
//
//  A second "Distance Apart" Lock Screen widget option, registered as its own Widget/kind so it
//  shows up as a separate, independently-selectable choice in the widget gallery alongside
//  DistanceWidget's big-circles-and-heart layout. Reuses that file's DistanceProvider/
//  DistanceEntry directly — both widgets need identical data, just laid out differently: both
//  initials together inside one heart (CoupleHeartInitials) beside the distance (rather than big
//  separate circles above it), with both cities on their own line underneath.
//

import SwiftUI
import WidgetKit

struct DistanceCompactWidgetView: View {
    let entry: DistanceEntry

    /// Both initials together inside one heart, rather than two separate circles — sits beside
    /// the distance rather than above it, so it stays small.
    private var heartPair: some View {
        CoupleHeartInitials(myInitial: personInitial(entry.myName), partnerInitial: personInitial(entry.partnerName))
    }

    /// Second line under the circles+distance row — a single city when together (pairs with
    /// "We're together!" replacing the distance itself above), the usual "City ↔ City" otherwise.
    /// Showing "Melbourne ↔ Melbourne" for a same-city couple would technically be correct but
    /// reads as a bug, not a feature.
    @ViewBuilder
    private var cityLine: some View {
        if entry.isSameCity, let myCity = entry.myCity {
            Text(myCity)
        } else if let myCity = entry.myCity, let partnerCity = entry.partnerCity {
            Text("\(myCity) ↔ \(partnerCity)")
        }
    }

    var body: some View {
        Group {
            if entry.myCity == nil || entry.partnerCity == nil {
                HStack(spacing: 4) {
                    heartPair
                    Text("Add your home cities")
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        heartPair
                        if entry.isSameCity {
                            Text("We're together!").font(.headline)
                        } else if let distanceLabel = entry.distanceLabel {
                            Text(distanceLabel).font(.headline)
                        }
                    }
                    cityLine
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        // Content sized to its own intrinsic width/height by default, leaving the rest of the
        // (margin-free, `.contentMarginsDisabled()`) rectangular slot empty instead of the row
        // actually filling it edge to edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "twofold://home"))
    }
}

struct DistanceCompactWidget: Widget {
    let kind = "DistanceCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DistanceProvider()) { entry in
            DistanceCompactWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Distance Apart (Compact)")
        .description("Distance and both cities together in one compact Lock Screen widget.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .accessoryRectangular) {
    DistanceCompactWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: "6,060 km", isSameCity: false, myCity: "Melbourne", partnerCity: "Singapore", myName: "Rosa", partnerName: "Dara")
}

#Preview("Same city", as: .accessoryRectangular) {
    DistanceCompactWidget()
} timeline: {
    DistanceEntry(date: .now, distanceLabel: nil, isSameCity: true, myCity: "Melbourne", partnerCity: "Melbourne", myName: "Rosa", partnerName: "Dara")
}
