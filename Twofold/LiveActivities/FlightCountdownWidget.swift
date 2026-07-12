//
//  FlightCountdownWidget.swift
//  LiveActivities
//
//  Premium tier — reuses WidgetSellView.swift's countdownWidget mockup design. First widget
//  needing a ticking multi-entry timeline: WidgetKit's reload budget is limited, so rather than
//  asking the OS to reload every minute, one getTimeline call generates a tiered run of future
//  entries (dense near the target, sparse further out) and WidgetKit just walks through them.
//

import SwiftUI
import WidgetKit

struct FlightCountdownEntry: TimelineEntry {
    let date: Date
    let isSubscriptionActive: Bool
    let targetDate: Date?
    let isDeparted: Bool
    let originCity: String?
    let destinationCity: String?
}

struct FlightCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlightCountdownEntry {
        FlightCountdownEntry(date: .now, isSubscriptionActive: true, targetDate: .now.addingTimeInterval(3600 * 5), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore")
    }

    func getSnapshot(in context: Context, completion: @escaping (FlightCountdownEntry) -> Void) {
        completion(entries(from: WidgetSnapshot.read()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightCountdownEntry>) -> Void) {
        let all = entries(from: WidgetSnapshot.read())
        // .atEnd re-invokes getTimeline once the tiered run is exhausted, which naturally
        // re-reads whatever the main app has written to the snapshot by then.
        completion(Timeline(entries: all, policy: .atEnd))
    }

    private func entries(from snapshot: WidgetSnapshot?) -> [FlightCountdownEntry] {
        let isSubscriptionActive = snapshot?.isSubscriptionActive ?? false
        guard let flight = snapshot?.nextFlight else {
            return [FlightCountdownEntry(date: .now, isSubscriptionActive: isSubscriptionActive, targetDate: nil, isDeparted: false, originCity: nil, destinationCity: nil)]
        }

        let now = Date.now
        let isDeparted = (flight.bestDeparture ?? .distantFuture) <= now
        let target = isDeparted ? flight.bestArrival : flight.bestDeparture

        guard let target else {
            return [FlightCountdownEntry(date: now, isSubscriptionActive: isSubscriptionActive, targetDate: nil, isDeparted: isDeparted, originCity: flight.originCity, destinationCity: flight.destinationCity)]
        }

        return Self.tieredDates(from: now, to: target).map { date in
            FlightCountdownEntry(date: date, isSubscriptionActive: isSubscriptionActive, targetDate: target, isDeparted: isDeparted, originCity: flight.originCity, destinationCity: flight.destinationCity)
        }
    }

    /// Dense near the target, sparse further out — 60s apart inside the final 10 minutes, 5
    /// minutes apart inside the final hour, 30 minutes apart beyond that. Capped well under
    /// WidgetKit's practical per-timeline entry budget.
    static func tieredDates(from now: Date, to target: Date, cap: Int = 200) -> [Date] {
        guard target > now else { return [now] }
        var dates: [Date] = []
        var cursor = now
        while cursor < target, dates.count < cap {
            dates.append(cursor)
            let remaining = target.timeIntervalSince(cursor)
            let step: TimeInterval = remaining <= 600 ? 60 : (remaining <= 3600 ? 300 : 1800)
            cursor = cursor.addingTimeInterval(step)
        }
        dates.append(target)
        return dates
    }
}

struct FlightCountdownWidgetView: View {
    let entry: FlightCountdownEntry

    private var remainingLabel: String {
        guard let targetDate = entry.targetDate else { return "—" }
        let remaining = max(0, targetDate.timeIntervalSince(entry.date))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private var caption: String {
        guard entry.targetDate != nil else { return "No upcoming flight" }
        return entry.isDeparted ? "until \(entry.destinationCity ?? "arrival")" : "until departure"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "airplane.departure")
                .font(.title3)
            Spacer()
            Text(entry.targetDate != nil ? remainingLabel : "✈️")
                .font(.system(size: 30, weight: .bold, design: .rounded))
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
            LinearGradient(colors: [Color(hex: "0B3D91"), Color(hex: "1C7ED6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 60))
                .opacity(0.18)
                .foregroundStyle(.white)
                .offset(x: 16, y: 16)
        }
        .widgetLock(!entry.isSubscriptionActive)
        .widgetURL(URL(string: "twofold://paywall"))
    }
}

struct FlightCountdownWidget: Widget {
    let kind = "FlightCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlightCountdownProvider()) { entry in
            FlightCountdownWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Flight Countdown")
        .description("Time until your next flight departs or lands.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, isSubscriptionActive: true, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore")
}
