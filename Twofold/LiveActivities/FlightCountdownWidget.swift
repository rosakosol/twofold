//
//  FlightCountdownWidget.swift
//  LiveActivities
//
//  Plus tier (reunion/flight countdown, per the widget matrix) — reuses WidgetSellView.swift's
//  countdownWidget mockup design. First widget needing a ticking multi-entry timeline:
//  WidgetKit's reload budget is limited, so rather than asking the OS to reload every minute,
//  one getTimeline call generates a tiered run of future entries (dense near the target, sparse
//  further out) and WidgetKit just walks through them.
//

import SwiftUI
import WidgetKit

struct FlightCountdownEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let targetDate: Date?
    let isDeparted: Bool
    let originCity: String?
    let destinationCity: String?
    let flightNumber: String?
    let flightID: UUID?
    let travelerIsMe: Bool?
    let myName: String
    let partnerName: String
}

struct FlightCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlightCountdownEntry {
        FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 5), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
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
        let subscriptionTier = snapshot?.subscriptionTier
        let myName = snapshot?.myName ?? "You"
        let partnerName = snapshot?.partnerName ?? "Partner"
        guard let flight = snapshot?.nextFlight else {
            return [FlightCountdownEntry(date: .now, subscriptionTier: subscriptionTier, targetDate: nil, isDeparted: false, originCity: nil, destinationCity: nil, flightNumber: nil, flightID: nil, travelerIsMe: nil, myName: myName, partnerName: partnerName)]
        }

        let now = Date.now
        let isDeparted = (flight.bestDeparture ?? .distantFuture) <= now
        let target = isDeparted ? flight.bestArrival : flight.bestDeparture

        guard let target else {
            return [FlightCountdownEntry(date: now, subscriptionTier: subscriptionTier, targetDate: nil, isDeparted: isDeparted, originCity: flight.originCity, destinationCity: flight.destinationCity, flightNumber: flight.flightNumber, flightID: flight.id, travelerIsMe: flight.travelerIsMe, myName: myName, partnerName: partnerName)]
        }

        return Self.tieredDates(from: now, to: target).map { date in
            FlightCountdownEntry(date: date, subscriptionTier: subscriptionTier, targetDate: target, isDeparted: isDeparted, originCity: flight.originCity, destinationCity: flight.destinationCity, flightNumber: flight.flightNumber, flightID: flight.id, travelerIsMe: flight.travelerIsMe, myName: myName, partnerName: partnerName)
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

    @Environment(\.widgetFamily) private var family

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }

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

    /// Locked → paywall (existing convention). Unlocked → this exact flight's tracking screen
    /// when there is one, otherwise Passport (where flights are viewed/added).
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let flightID = entry.flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
        return URL(string: "twofold://passport")
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessoryRectangular
            } else {
                homeScreenBody
            }
        }
        .widgetURL(deepLinkURL)
    }

    @ViewBuilder
    private var accessoryRectangular: some View {
        if isLocked {
            Label("Twofold Plus", systemImage: "lock.fill")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label(entry.targetDate != nil ? remainingLabel : "No upcoming flight", systemImage: "airplane.departure")
                    .font(.headline)
                if entry.targetDate != nil {
                    Text(caption).font(.caption2)
                }
            }
        }
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let travelerIsMe = entry.travelerIsMe {
                    WidgetAvatarView(person: travelerIsMe ? .me : .partner, name: travelerIsMe ? entry.myName : entry.partnerName, size: 22)
                } else {
                    Image(systemName: "airplane.departure").font(.title3)
                }
                if let data = WidgetImageCache.readAirlineLogoImage(), let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                if let flightNumber = entry.flightNumber {
                    Text(flightNumber).font(.caption2.weight(.bold))
                }
            }
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
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
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
        .description("Time until your next flight departs or lands, on your Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
}
