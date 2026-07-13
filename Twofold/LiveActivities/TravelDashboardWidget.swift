//
//  TravelDashboardWidget.swift
//  LiveActivities
//
//  Premium tier — the .systemLarge travel-themed composite: flight count, countries visited,
//  distance travelled (WidgetSnapshot.TravelStats, sourced from PassportView's FlightStats), plus
//  a teaser for the next upcoming trip. MeasurementPreference.distanceLabel(km:) is already
//  shared with this target (see project.pbxproj membership exceptions), so distance formatting
//  matches the main app's unit preference exactly rather than hardcoding km.
//

import SwiftUI
import WidgetKit

struct TravelDashboardEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let flightCount: Int
    let countryCount: Int
    let totalDistanceKm: Double
    let nextTripDestination: String?
    let nextTripDate: Date?
}

struct TravelDashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> TravelDashboardEntry {
        TravelDashboardEntry(date: .now, subscriptionTier: WidgetTier.premium, flightCount: 14, countryCount: 4, totalDistanceKm: 84392, nextTripDestination: "Tokyo", nextTripDate: .now.addingTimeInterval(86400 * 21))
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelDashboardEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelDashboardEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(21600)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> TravelDashboardEntry {
        let stats = snapshot?.travelStats
        return TravelDashboardEntry(
            date: .now,
            subscriptionTier: snapshot?.subscriptionTier,
            flightCount: stats?.flightCount ?? 0,
            countryCount: stats?.countryCount ?? 0,
            totalDistanceKm: stats?.totalDistanceKm ?? 0,
            nextTripDestination: stats?.nextTripDestination,
            nextTripDate: stats?.nextTripDate
        )
    }
}

struct TravelDashboardWidgetView: View {
    let entry: TravelDashboardEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://passport") }

    private var nextTripLabel: String? {
        guard let destination = entry.nextTripDestination, let date = entry.nextTripDate else { return nil }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0)
        return "\(destination) in \(days) day\(days == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Travel Dashboard")
                    .font(.headline)
                Spacer()
                if let nextTripLabel {
                    Label(nextTripLabel, systemImage: "airplane.departure")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            // Clears the brand mark's corner footprint.
            .padding(.trailing, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(value: "\(entry.flightCount)", label: "Flights", icon: "airplane")
                statTile(value: "\(entry.countryCount)", label: "Countries", icon: "globe.americas.fill")
                statTile(value: MeasurementPreference.distanceLabel(km: entry.totalDistanceKm), label: "Distance", icon: "arrow.left.and.right")
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "0B3D91"), Color(hex: "1C7ED6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).opacity(0.85)
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).opacity(0.85).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TravelDashboardWidget: Widget {
    let kind = "TravelDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TravelDashboardProvider()) { entry in
            TravelDashboardWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Travel Dashboard")
        .description("Flights, distance, and countries at a glance.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemLarge) {
    TravelDashboardWidget()
} timeline: {
    TravelDashboardEntry(date: .now, subscriptionTier: WidgetTier.premium, flightCount: 14, countryCount: 4, totalDistanceKm: 84392, nextTripDestination: "Tokyo", nextTripDate: .now.addingTimeInterval(86400 * 21))
}
