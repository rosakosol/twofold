//
//  FlightCountdownWidget.swift
//  LiveActivities
//
//  Plus tier, flight-specific countdown — was "TripCountdownWidget" (display name only; `kind`
//  was always "FlightCountdownWidget", left unchanged across that earlier half-finished rename
//  to avoid orphaning placed instances). Now genuinely flight-specific *and* user-configurable:
//  long-press → Edit Widget lets the user pick which of the couple's currently-tracked flights
//  (`SelectFlightIntent`/`TrackedFlightEntity`, see TrackedFlightEntity.swift) this widget counts
//  down to, rather than always defaulting to the soonest one. This app's first App
//  Intents–configured widget — every other widget here uses plain StaticConfiguration.
//
//  Home Screen (.systemSmall) and, new, Lock Screen (.accessoryRectangular/.accessoryCircular).
//  Still the app's first widget needing a ticking multi-entry timeline: WidgetKit's reload budget
//  is limited, so rather than asking the OS to reload every minute, one timeline call generates a
//  tiered run of future entries (dense near the target, sparse further out) and WidgetKit just
//  walks through them.
//

import AppIntents
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

struct FlightCountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlightCountdownEntry {
        FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 5), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
    }

    func snapshot(for configuration: SelectFlightIntent, in context: Context) async -> FlightCountdownEntry {
        entries(for: configuration, from: WidgetSnapshot.read()).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectFlightIntent, in context: Context) async -> Timeline<FlightCountdownEntry> {
        let all = entries(for: configuration, from: WidgetSnapshot.read())
        // .atEnd re-invokes timeline(for:in:) once the tiered run is exhausted, which naturally
        // re-reads whatever the main app has written to the snapshot by then.
        return Timeline(entries: all, policy: .atEnd)
    }

    /// Resolves which flight this instance counts down to: the user's picked flight if it's
    /// still among the couple's currently-tracked ones, otherwise the soonest tracked flight
    /// (an unconfigured widget, or one whose picked flight has since landed/been removed,
    /// degrades to the same "always the nearest flight" behavior this widget always had).
    private func selectedFlight(for configuration: SelectFlightIntent, snapshot: WidgetSnapshot?) -> WidgetSnapshot.FlightInfo? {
        let tracked = snapshot?.trackedFlights ?? []
        if let selectedID = configuration.flight?.id, let match = tracked.first(where: { $0.id == selectedID }) {
            return match
        }
        return tracked.first ?? snapshot?.nextFlight
    }

    private func entries(for configuration: SelectFlightIntent, from snapshot: WidgetSnapshot?) -> [FlightCountdownEntry] {
        let subscriptionTier = snapshot?.subscriptionTier
        let myName = snapshot?.myName ?? "You"
        let partnerName = snapshot?.partnerName ?? "Partner"
        guard let flight = selectedFlight(for: configuration, snapshot: snapshot) else {
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

    /// Compact single-unit form for the small Lock Screen circle — "2h"/"45m" rather than the
    /// combined "2h 10m" the rectangular/Home Screen views have room for.
    private var compactRemainingLabel: String {
        guard let targetDate = entry.targetDate else { return "—" }
        let remaining = max(0, targetDate.timeIntervalSince(entry.date))
        let hours = Int(remaining) / 3600
        if hours > 0 { return "\(hours)h" }
        return "\(Int(remaining) / 60)m"
    }

    private var caption: String {
        guard entry.targetDate != nil else { return "No upcoming trip" }
        return entry.isDeparted ? "until \(entry.destinationCity ?? "arrival")" : "until departure"
    }

    /// Locked → paywall (existing convention). Unlocked → this exact flight's tracking screen
    /// when there is one, otherwise Passport (where trips/flights are viewed/added).
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let flightID = entry.flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
        return URL(string: "twofold://passport")
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
        .widgetURL(deepLinkURL)
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

    /// Lock Screen widgets are never tier-gated in this app (a blur+lock overlay doesn't render
    /// sensibly in the system's monochrome accessory rendering mode) — same as every other
    /// Lock Screen widget here (Distance, Days Together, Trip Countdown).
    @ViewBuilder
    private var accessoryRectangular: some View {
        if entry.targetDate != nil {
            VStack(alignment: .leading, spacing: 1) {
                Label("\(entry.flightNumber ?? "Flight") · \(remainingLabel)", systemImage: "airplane")
                    .font(.headline)
                Text(caption)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Label("No tracked flight", systemImage: "airplane")
        }
    }

    @ViewBuilder
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.targetDate != nil {
                VStack(spacing: 0) {
                    Text(compactRemainingLabel).font(.system(.title3, design: .rounded).bold())
                    Text("to go").font(.caption2)
                }
            } else {
                Image(systemName: "airplane")
            }
        }
    }

    /// The Lock Screen's single text-line slot — flight number + remaining time only, no room
    /// for the departure/arrival caption the other families have.
    @ViewBuilder
    private var accessoryInline: some View {
        if entry.targetDate != nil {
            Label("\(entry.flightNumber ?? "Flight") in \(remainingLabel)", systemImage: "airplane")
        } else {
            Label("No tracked flight", systemImage: "airplane")
        }
    }
}

struct FlightCountdownWidget: Widget {
    // Deliberately unchanged from before this file's own rename — see the file header.
    let kind = "FlightCountdownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectFlightIntent.self, provider: FlightCountdownProvider()) { entry in
            FlightCountdownWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Flight Countdown")
        .description("Time until a chosen flight departs or arrives.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
}

#Preview(as: .accessoryRectangular) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
}

#Preview(as: .accessoryCircular) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
}

#Preview(as: .accessoryInline) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry(date: .now, subscriptionTier: WidgetTier.plus, targetDate: .now.addingTimeInterval(3600 * 2 + 600), isDeparted: true, originCity: "Melbourne", destinationCity: "Singapore", flightNumber: "QF31", flightID: nil, travelerIsMe: true, myName: "You", partnerName: "Partner")
}
