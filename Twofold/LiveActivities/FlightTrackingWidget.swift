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
            partnerName: snapshot?.partnerName ?? "Partner"
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

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }

    private var delayLabel: String? {
        guard let delaySeconds = entry.delaySeconds, delaySeconds > 300 else { return nil }
        let minutes = delaySeconds / 60
        return minutes >= 60 ? "+\(minutes / 60)h \(minutes % 60)m" : "+\(minutes)m"
    }

    /// True once the *departure* has actually happened — same "which leg's estimate is
    /// relevant right now" logic WidgetSnapshotWriter uses to pick delaySeconds' source leg.
    private var isDeparted: Bool { (entry.bestDeparture ?? .distantFuture) <= entry.date }

    /// "Departs 3:45 PM" pre-departure, "Arrives 9:20 PM" once airborne (or landed) — whichever
    /// leg's estimate is still actionable, in the device's local time (no per-airport timezone
    /// data reaches this widget, same as every other time shown here).
    private var etaLabel: String? {
        let target = isDeparted ? entry.bestArrival : entry.bestDeparture
        guard let target else { return nil }
        let time = target.formatted(date: .omitted, time: .shortened)
        return isDeparted ? "Arrives \(time)" : "Departs \(time)"
    }

    private var routeLabel: String? {
        guard let originCity = entry.originCity, let destinationCity = entry.destinationCity else { return nil }
        guard let originCode = entry.originCode, let destinationCode = entry.destinationCode else {
            return "\(originCity) → \(destinationCity)"
        }
        return "\(originCode) \(originCity) → \(destinationCode) \(destinationCity)"
    }

    /// Locked → paywall. Unlocked → this exact flight's tracking screen when there is one,
    /// otherwise Passport.
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let flightID = entry.flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
        return URL(string: "twofold://passport")
    }

    var body: some View {
        homeScreenBody
            .widgetURL(deepLinkURL)
    }

    // MARK: - Small / Medium

    @ViewBuilder
    private var homeScreenBody: some View {
        if let status = entry.status {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    airlineLogo(size: 16)
                    Text(entry.flightNumber ?? status.displayLabel)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    if let delayLabel {
                        Text(delayLabel)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                }
                .padding(.trailing, 20)

                Spacer(minLength: 0)

                Text(status.displayLabel)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                progressRail(markerSize: 26)
                    .padding(.vertical, 2)

                if let routeLabel {
                    Text(routeLabel)
                        .font(.caption2)
                        .opacity(0.85)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if let etaLabel {
                    Text(etaLabel)
                        .font(.caption2.weight(.semibold))
                        .opacity(0.95)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [LiveActivityPalette.color(for: status), LiveActivityPalette.color(for: status).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .widgetBranded()
            .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
        } else {
            emptyState
                .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func airlineLogo(size: CGFloat) -> some View {
        if let data = WidgetImageCache.readAirlineLogoImage(), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    /// Solid line up to the current progress, dashed the rest of the way — same visual language
    /// as JourneyLockScreenView.progressRail — but the marker riding it is the traveler's real
    /// avatar (WidgetAvatarView) when one's set, falling back to a plain plane glyph otherwise.
    private func progressRail(markerSize: CGFloat) -> some View {
        GeometryReader { geo in
            let progressX = geo.size.width * min(1, max(0, entry.progress))
            let midY = geo.size.height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: progressX, y: midY))
                }
                .stroke(.white, lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: progressX, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

                Group {
                    if let travelerIsMe = entry.travelerIsMe {
                        WidgetAvatarView(
                            person: travelerIsMe ? .me : .partner,
                            name: travelerIsMe ? entry.myName : entry.partnerName,
                            size: markerSize
                        )
                    } else {
                        ZStack {
                            Circle().fill(.white.opacity(0.9))
                            Image(systemName: "airplane")
                                .font(.system(size: markerSize * 0.45, weight: .bold))
                                .foregroundStyle(LiveActivityPalette.color(for: status))
                        }
                        .frame(width: markerSize, height: markerSize)
                    }
                }
                .position(x: progressX, y: midY)
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }

    private var status: FlightStatus? { entry.status }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "airplane.circle").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("No upcoming flight").font(.caption2).multilineTextAlignment(.center).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FlightTrackingWidget: Widget {
    let kind = "FlightTrackingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlightTrackingProvider()) { entry in
            FlightTrackingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Flight Tracking")
        .description("Live status and route, on your Home Screen.")
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
