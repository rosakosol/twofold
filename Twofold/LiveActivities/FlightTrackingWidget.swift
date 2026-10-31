//
//  FlightTrackingWidget.swift
//  LiveActivities
//
//  Plus tier — replaces FlightStatusWidget. Whose flight it is in the corner (the traveller's photo,
//  yours or the partner's, or the airline's logo when no passenger is set), "Lands in 55m" large, and the
//  plane riding a progress rail. The photo used to ride the rail instead of the plane; it moved up
//  beside the flight number so the rail reads as the journey at a glance, the same as the Lock
//  Screen Live Activity.
//  Small and Medium share the same layout (like DrawingPadWidget); Medium adds the status and
//  route underneath. There's no route map here (that was Large-only and got dropped along with
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

        // On the minute marks before take-off and touchdown, so the big "55m" is right to the
        // minute (see `TimeMath.countdownMoments`), with take-off and touchdown themselves among
        // them. The rail moves on the same entries. WidgetKit's daily budget counts reloads, not
        // entries, so a dense timeline costs one reload like a sparse one; the cap only bounds the
        // work of rendering it ahead.
        let targets = [flight?.bestDeparture, flight?.bestArrival].compactMap { $0 }
        let dates = TimeMath.countdownMoments(to: targets, from: now).prefix(150)

        let entries = dates.map { entry(from: snapshot, at: $0) }
        // Nothing to count down to: look again in fifteen minutes, as before.
        let nextRefresh = dates.count > 1 ? dates.last! : now.addingTimeInterval(900)
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

    /// Whose flight it is decides the header (section 7): the traveller's own photo, yours or the
    /// partner's, and the airline's logo only when nobody is set.
    private var isMine: Bool { entry.travelerIsMe == true }

    /// Only a flight with the partner actually on it shows their photo. One with no passenger set
    /// (`travelerIsMe` nil) used to be read as theirs, which put the partner's face on what was
    /// often your own flight; it gets the airline's logo, which claims it for neither of you.
    private var isPartners: Bool { entry.travelerIsMe == false }

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
        // No flight to show: Travel, where one is added, rather than the Stats tab it used to open.
        return URL(string: "twofold://travel")
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
                Spacer(minLength: 0)
                progressRail(markerSize: 30)
            }
            // Medium only: the small widget is the photo, the countdown and the rail, nothing else.
            if family == .systemMedium {
                Text(routeLine(status: status))
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.92)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// Photo or logo, the flight number, and a delay pill when there is one.
    private var header: some View {
        HStack(spacing: 8) {
            if isPartners {
                WidgetAvatarView(person: .partner, name: entry.partnerName, size: 34)
            } else if isMine {
                WidgetAvatarView(person: .me, name: entry.myName, size: 34)
            } else {
                airlineLogo(size: 34)
            }
            Text(entry.flightNumber ?? "")
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    /// "Departs in" or "Lands in", then the time left: "55m", "3h 12m", "2d 4h".
    ///
    /// A string per timeline entry rather than `Text(_, style: .relative)`, which can only say
    /// "55 min" and has no form short enough to stand this large. The provider puts an entry on
    /// every minute mark of the last hour, so it is still right to the minute.
    @ViewBuilder
    private func countdown(status: FlightStatus) -> some View {
        Text(isDeparted ? "Lands in" : "Departs in")
            .font(.system(size: 15, weight: .semibold))
            .opacity(0.92)
        if let target, target > entry.date {
            Text(TimeMath.compactDuration(target.timeIntervalSince(entry.date)))
                .font(.system(size: 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
        } else {
            Text(status.displayLabel)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }

    /// Your own flight on the day: where to go and when (section 7). There is no boarding time in
    /// the flight data, so the terminal stands in its place rather than an invented one.
    ///
    /// Three columns fit a medium widget but not a small one, where a third of the width wrapped
    /// "Terminal" and "Departs" mid-word and cut the time to "11:1…". Small puts the departure
    /// time on a line of its own under the other two.
    @ViewBuilder
    private var travelDayDetails: some View {
        let gate = detail("Gate", entry.originGate ?? "—")
        let terminal = detail("Terminal", entry.originTerminal ?? "—")
        let departs = detail("Departs", entry.bestDeparture.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 16) { gate; terminal }
                departs
            }
        } else {
            HStack(alignment: .top, spacing: 12) { gate; terminal; departs }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
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
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            Image(systemName: "airplane").font(.system(size: size * 0.7, weight: .bold))
                .frame(width: size, height: size)
        }
    }

    /// The journey as a line: white where it has flown, faint where it has yet to, a dot at the
    /// destination, and the plane in a white disc riding it. Whose flight it is lives in the
    /// header, so the marker is always the plane.
    private func progressRail(markerSize: CGFloat) -> some View {
        GeometryReader { geo in
            let inset = markerSize / 2
            let travel = max(0, geo.size.width - markerSize)
            let progressX = inset + travel * min(1, max(0, entry.progress))
            let midY = geo.size.height / 2
            ZStack {
                Capsule().fill(.white.opacity(0.3)).frame(width: travel, height: 5)
                    .position(x: geo.size.width / 2, y: midY)
                Circle().fill(.white.opacity(0.45)).frame(width: 7, height: 7)
                    .position(x: inset + travel, y: midY)
                Capsule().fill(.white).frame(width: max(0, progressX - inset), height: 5)
                    .position(x: inset + max(0, progressX - inset) / 2, y: midY)
                Image(systemName: "airplane")
                    .font(.system(size: markerSize * 0.45, weight: .bold))
                    // The gradient's own blue, fixed: the disc is white in both appearances.
                    .foregroundStyle(Color(hex: 0x1A6FD6))
                    .frame(width: markerSize, height: markerSize)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
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
        .configurationDisplayName("Flight tracking")
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
