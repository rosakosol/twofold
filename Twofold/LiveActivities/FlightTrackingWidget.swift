//
//  FlightTrackingWidget.swift
//  LiveActivities
//
//  Plus tier — replaces FlightStatusWidget. Mirrors the in-app progress-rail treatment
//  (JourneyLockScreenView's progressRail: solid-to-dashed line + a marker riding the current
//  progress), but rides the traveler's avatar instead of a plain plane icon when one's set —
//  same idea as FlightMapView's travelerMarker. Small and Medium share the same layout (like
//  DrawingPadWidget) — there's no route map here (that was Large-only and got dropped along with
//  the WidgetSnapshotWriter map-rendering pipeline it needed).
//

import SwiftUI
import WidgetKit

struct FlightTrackingEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let status: FlightStatus?
    let originCity: String?
    let destinationCity: String?
    let originCode: String?
    let destinationCode: String?
    let flightNumber: String?
    let flightID: UUID?
    let delaySeconds: Int?
    let bestDeparture: Date?
    let bestArrival: Date?
    let progress: Double
    let travelerIsMe: Bool?
    let myName: String
    let partnerName: String
    var originGate: String? = nil
    var originTerminal: String? = nil
}

struct FlightTrackingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlightTrackingEntry {
        FlightTrackingEntry(
            date: .now, subscriptionTier: WidgetTier.plus, status: .inAir,
            originCity: "Melbourne", destinationCity: "Singapore", originCode: "MEL", destinationCode: "SIN",
            flightNumber: "QF31", flightID: nil, delaySeconds: nil,
            bestDeparture: .now.addingTimeInterval(-3600 * 3), bestArrival: .now.addingTimeInterval(3600 * 5), progress: 0.4,
            travelerIsMe: true, myName: "You", partnerName: "Partner"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FlightTrackingEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read(), at: .now))
    }

    /// Several entries, not one.
    ///
    /// This used to hand WidgetKit a single entry holding the status and progress exactly as the
    /// main app last wrote them, then ask to be called again in fifteen minutes — where it read
    /// the same stored values and rendered the same thing. So a flight the app had last seen as
    /// scheduled stayed "Scheduled" on the Home Screen through boarding, take-off and landing,
    /// because nothing between those moments ever reruns the app. The reported case was a flight
    /// stuck at Scheduled while it was in the air.
    ///
    /// The snapshot carries the departure and arrival times, which is enough for the widget to
    /// move itself along: each entry re-derives status and progress for its own moment, and there
    /// are entries at the two times the display actually changes character. WidgetKit renders
    /// them at those instants without the app running at all.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightTrackingEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let flight = snapshot?.nextFlight
        let now = Date.now

        // The moments worth a guaranteed entry: take-off and touchdown, plus a coarse walk across
        // the flight so the progress rail creeps forward rather than jumping a quarter at a time.
        var moments: Set<Date> = [now]
        if let departure = flight?.bestDeparture, departure > now { moments.insert(departure) }
        if let arrival = flight?.bestArrival, arrival > now { moments.insert(arrival) }
        for minutes in stride(from: 15, through: 240, by: 15) {
            moments.insert(now.addingTimeInterval(Double(minutes) * 60))
        }
        // A cap well under WidgetKit's own, since it budgets refreshes per widget per day and
        // there is no value in a denser walk than the rail can visibly show.
        let dates = moments.sorted().prefix(24)

        let entries = dates.map { entry(from: snapshot, at: $0) }
        let nextRefresh = dates.last ?? now.addingTimeInterval(900)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func entry(from snapshot: WidgetSnapshot?, at date: Date) -> FlightTrackingEntry {
        let flight = snapshot?.nextFlight
        return FlightTrackingEntry(
            date: date,
            subscriptionTier: snapshot?.subscriptionTier,
            status: flight?.status.projected(departure: flight?.bestDeparture, arrival: flight?.bestArrival, now: date),
            originCity: flight?.originCity,
            destinationCity: flight?.destinationCity,
            originCode: flight?.originCode,
            destinationCode: flight?.destinationCode,
            flightNumber: flight?.flightNumber,
            flightID: flight?.id,
            delaySeconds: flight?.delaySeconds,
            bestDeparture: flight?.bestDeparture,
            bestArrival: flight?.bestArrival,
            // Recomputed for this entry's own moment. The stored value was correct when the app
            // last ran and has been frozen ever since, so the rail never moved between openings.
            progress: Self.progress(for: flight, at: date),
            travelerIsMe: flight?.travelerIsMe,
            myName: snapshot?.myName ?? "You",
            partnerName: snapshot?.partnerName ?? "Partner",
            originGate: flight?.originGate,
            originTerminal: flight?.originTerminal
        )
    }

    /// Mirrors `Flight.progress`, evaluated at an arbitrary moment rather than "now" — same
    /// guard, so an arrival that isn't after its departure can't produce a NaN.
    private static func progress(for flight: WidgetSnapshot.FlightInfo?, at date: Date) -> Double {
        guard let flight else { return 0 }
        guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else {
            return flight.progress
        }
        return min(1, max(0, date.timeIntervalSince(departure) / arrival.timeIntervalSince(departure)))
    }
}

struct FlightTrackingWidgetView: View {
    let entry: FlightTrackingEntry
    @Environment(\.widgetFamily) private var family

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }

    /// Whose flight it is decides the layout (section 7): the partner's leads with their photo, your
    /// own with the airline's logo. Nobody set reads as the partner's, the common case.
    private var isMine: Bool { entry.travelerIsMe == true }

    private var isDeparted: Bool { (entry.bestDeparture ?? .distantFuture) <= entry.date }
    private var target: Date? { isDeparted ? entry.bestArrival : entry.bestDeparture }

    /// Today, not yet gone: when the gate matters more than the countdown.
    private var isTravelDay: Bool {
        guard let departure = entry.bestDeparture, !isDeparted else { return false }
        return Calendar.current.isDate(departure, inSameDayAs: entry.date)
    }

    private var delayMinutes: Int? {
        guard let delaySeconds = entry.delaySeconds, delaySeconds > 300 else { return nil }
        return delaySeconds / 60
    }

    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let flightID = entry.flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
        return URL(string: "twofold://passport")
    }

    var body: some View {
        Group {
            if let status = entry.status {
                content(status: status)
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary(status: status))
                    .widgetSurface(Brand.flight)
            } else {
                WidgetEmptyState(systemImage: "airplane", message: "No upcoming flight", gradient: Brand.flight)
            }
        }
        .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    private func content(status: FlightStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if status == .cancelled || status == .diverted {
                Text(status.displayLabel)
                    .font(.system(size: 26, weight: .bold))
                    .widgetAccentable()
            } else if isMine && isTravelDay {
                travelDayDetails
            } else {
                countdown(status: status)
                progressRail(markerSize: 24)
            }
            Text(routeLine(status: status))
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Photo or logo, the flight number, and a delay pill when there is one.
    private var header: some View {
        HStack(spacing: 6) {
            if isMine {
                airlineLogo(size: 22)
            } else {
                WidgetAvatarView(person: .partner, name: entry.partnerName, size: 26)
            }
            Text(entry.flightNumber ?? "")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let delayMinutes {
                // "Delayed 6 min" (section 7): the warning colours on a white pill, icon and word,
                // never colour alone. Fixed values, since the flight gradient is the same in both
                // appearances.
                Label("Delayed \(delayMinutes) min", systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9A5A0B))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white, in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// "Departs in" or "Lands in", then the time left, counting down live.
    @ViewBuilder
    private func countdown(status: FlightStatus) -> some View {
        Text(isDeparted ? "Lands in" : "Departs in")
            .font(.system(size: 12, weight: .semibold))
            .opacity(0.92)
        if let target, target > entry.date {
            Text(target, style: .relative)
                .font(.system(size: family == .systemMedium ? 30 : 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        } else {
            Text(status.displayLabel)
                .font(.system(size: 24, weight: .bold))
                .widgetAccentable()
        }
    }

    /// Your own flight on the day: where to go and when (section 7). There is no boarding time in
    /// the flight data, so the terminal stands in its place rather than an invented one.
    private var travelDayDetails: some View {
        HStack(alignment: .top, spacing: 12) {
            detail("Gate", entry.originGate ?? "—")
            detail("Terminal", entry.originTerminal ?? "—")
            detail("Departs", entry.bestDeparture.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.92)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }

    /// One sentence for VoiceOver (section 9): "Flight UA506, 86% complete, lands in 1 hour 7
    /// minutes".
    private func accessibilitySummary(status: FlightStatus) -> String {
        var parts = ["Flight \(entry.flightNumber ?? "")"]
        if isDeparted, status != .cancelled, status != .diverted {
            parts.append("\(Int((entry.progress * 100).rounded()))% complete")
        }
        if let target, target > entry.date {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = target.timeIntervalSince(entry.date) >= 86_400 ? [.day, .hour] : [.hour, .minute]
            formatter.unitsStyle = .full
            if let remaining = formatter.string(from: entry.date, to: target) {
                parts.append("\(isDeparted ? "lands" : "departs") in \(remaining)")
            }
        } else {
            parts.append(status.displayLabel)
        }
        if let delayMinutes { parts.append("delayed \(delayMinutes) minutes") }
        return parts.joined(separator: ", ")
    }

    private func routeLine(status: FlightStatus) -> String {
        let route = [entry.originCode, entry.destinationCode].compactMap { $0 }.joined(separator: " → ")
        guard family == .systemMedium else { return route }
        return "\(status.displayLabel) · \(route)"
    }

    @ViewBuilder
    private func airlineLogo(size: CGFloat) -> some View {
        if let uiImage = WidgetImageDecoding.downsampled(WidgetImageCache.readAirlineLogoImage(), pointSize: size) {
            Image(uiImage: uiImage)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "airplane").font(.system(size: size * 0.7, weight: .bold))
        }
    }

    /// The journey as a line, the traveller's photo (or the plane, for your own flight) as the
    /// marker riding it.
    private func progressRail(markerSize: CGFloat) -> some View {
        GeometryReader { geo in
            let inset = markerSize / 2
            let travel = max(0, geo.size.width - markerSize)
            let progressX = inset + travel * min(1, max(0, entry.progress))
            let midY = geo.size.height / 2
            ZStack {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    .position(x: geo.size.width / 2, y: midY)
                Capsule().fill(.white).frame(width: progressX, height: 4)
                    .position(x: progressX / 2, y: midY)
                Group {
                    if isMine {
                        Image(systemName: "airplane")
                            .font(.system(size: markerSize * 0.45, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1A6FD6))
                            .frame(width: markerSize, height: markerSize)
                            .background(.white, in: Circle())
                    } else {
                        WidgetAvatarView(person: .partner, name: entry.partnerName, size: markerSize)
                    }
                }
                .position(x: progressX, y: midY)
            }
        }
        .frame(height: markerSize + 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct FlightTrackingWidget: Widget {
    let kind = "FlightTrackingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlightTrackingProvider()) { entry in
            FlightTrackingWidgetView(entry: entry)
        }
        .configurationDisplayName("Flight Tracking")
        .description("Your next flight, or theirs: how long until it departs or lands, and where it is.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    FlightTrackingWidget()
} timeline: {
    FlightTrackingEntry(
        date: .now, subscriptionTier: WidgetTier.plus, status: .inAir,
        originCity: "Melbourne", destinationCity: "Singapore", originCode: "MEL", destinationCode: "SIN",
        flightNumber: "QF31", flightID: nil, delaySeconds: 720,
        bestDeparture: .now.addingTimeInterval(-3600 * 3), bestArrival: .now.addingTimeInterval(3600 * 5), progress: 0.4,
        travelerIsMe: true, myName: "You", partnerName: "Partner"
    )
}

#Preview(as: .systemMedium) {
    FlightTrackingWidget()
} timeline: {
    FlightTrackingEntry(
        date: .now, subscriptionTier: WidgetTier.plus, status: .inAir,
        originCity: "Melbourne", destinationCity: "Singapore", originCode: "MEL", destinationCode: "SIN",
        flightNumber: "QF31", flightID: nil, delaySeconds: 720,
        bestDeparture: .now.addingTimeInterval(-3600 * 3), bestArrival: .now.addingTimeInterval(3600 * 5), progress: 0.4,
        travelerIsMe: true, myName: "You", partnerName: "Partner"
    )
}
