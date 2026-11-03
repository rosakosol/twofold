//
//  FlightJourneyCard.swift
//  Twofold
//
//  Flight Details' summary of both legs: each airport, its local time, terminal and gate, and how
//  far away departure and arrival are.
//

import SwiftUI

struct FlightJourneyCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight

    /// Every time on this screen is that airport's own local time, because that is the number
    /// printed on the boarding pass and shown on the departure board. A UA60 leaving San Francisco
    /// at 23:20 has to read 11:20pm.
    ///
    /// This card used to render both legs in the viewer's home-city time instead, so that a glance
    /// answered "when do I need to be ready" with no conversion. That is a real question, but it is
    /// the second one — and answering it by relabelling the departure time silently made the
    /// summary disagree with the departure card below it. Home time is still here, on its own line
    /// underneath and only when it differs, which answers both without either being a guess.
    private var homeTimeZone: TimeZone { appModel.currentUser.homeCity?.timeZone ?? .current }

    /// Ticks with the header, for the same reason (FLT-11).
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            journeyCardContent(now: context.date)
        }
    }

    private func journeyCardContent(now: Date) -> some View {
        SectionCard {
            if flight.airlineName != nil || !flight.flightNumberIATA.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    AirlineLogoView(url: flight.displayLogoURL, size: 24)
                    Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
            }

            journeyRow(
                code: flight.origin.displayCode, city: flight.origin.displayName,
                time: flight.bestDeparture, timeZone: flight.origin.timeZone ?? homeTimeZone,
                terminal: flight.terminalOrigin, gate: flight.gateOrigin,
                statusLine: departureStatusLine(now: now)
            )

            HStack {
                Rectangle().fill(Theme.textSecondary.opacity(0.2)).frame(width: 2, height: 28).padding(.leading, 15)
                Spacer()
            }

            journeyRow(
                code: flight.destination.displayCode, city: flight.destination.displayName,
                time: flight.bestArrival, timeZone: flight.destination.timeZone ?? homeTimeZone,
                terminal: flight.terminalDestination, gate: flight.gateDestination,
                statusLine: arrivalStatusLine(now: now)
            )
        }
    }

    private func departureStatusLine(now: Date) -> String {
        // Checked before anything else — a cancelled/diverted flight's `bestDeparture` is often
        // still a real (now-past) scheduled timestamp, which fell through to the "Departing
        // shortly" branch below and contradicted the "Cancelled" badge shown right above it.
        if flight.status == .cancelled { return "Cancelled" }
        if flight.status == .diverted { return "Diverted" }
        // `actualOff` (wheels up) alone, without `actualOut` (gate pushback), still means this
        // flight has genuinely left — see `Flight.bestDeparture`'s doc comment. Without this,
        // that case fell through to the `bestDeparture` branch below with a past timestamp,
        // reading as "Departing shortly" for a flight that's actually been airborne for hours.
        if let departed = flight.actualOut ?? flight.actualOff { return "Departed \(Self.relativeShort(departed, now: now)) ago" }
        if let scheduled = flight.bestDeparture { return scheduled > now ? "Departs \(Self.relativeShort(scheduled, now: now))" : "Departing shortly" }
        return "Not available"
    }

    private func arrivalStatusLine(now: Date) -> String {
        if flight.status == .cancelled { return "Cancelled" }
        if flight.status == .diverted { return "Diverted" }
        if flight.actualIn != nil { return "Arrived \(Self.relativeShort(flight.actualIn!, now: now)) ago" }
        if let arrival = flight.bestArrival { return arrival > now ? "Arrives in \(Self.relativeShort(arrival, now: now))" : "Arriving shortly" }
        return "Not available"
    }

    private func journeyRow(code: String, city: String, time: Date?, timeZone: TimeZone?, terminal: String?, gate: String?, statusLine: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                Image(systemName: "airplane").font(.caption).foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(code) · \(city)").font(.headline).lineLimit(1).minimumScaleFactor(0.85)
                if let time {
                    // Falls back to the user's home city, not the device. When an airport's own
                    // zone is genuinely unknown, home time is at least the frame the rest of this
                    // screen is in, so nothing contradicts anything else. Falling back to the
                    // device made a departure read 8:20am on a phone that happened to be in UTC+2.
                    Text(time, format: Date.FormatStyle(timeZone: timeZone ?? homeTimeZone).day().month(.abbreviated).hour().minute())
                        .font(.subheadline.weight(.semibold))
                    if let homeLine = FlightTrackingView.homeTimeLine(for: time, airportZone: timeZone ?? homeTimeZone, homeZone: homeTimeZone) {
                        Text(homeLine)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("Time not available").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Text(Self.terminalGateLine(terminal: terminal, gate: gate))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(statusLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        // One coherent read ("LAX, Los Angeles, 12 Aug 10:45 AM, Terminal 4 · Gate 22, Departs in
        // 2 hours") instead of four separate swipes for what's a single journey leg.
        .accessibilityElement(children: .combine)
    }

    private static func terminalGateLine(terminal: String?, gate: String?) -> String {
        switch (terminal, gate) {
        case (.some(let t), .some(let g)): return "Terminal \(t) · Gate \(g)"
        case (.some(let t), nil): return "Terminal \(t) · Gate not available"
        case (nil, .some(let g)): return "Gate \(g)"
        case (nil, nil): return "Terminal & gate not available"
        }
    }

    private static func relativeShort(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now).replacingOccurrences(of: "in ", with: "").replacingOccurrences(of: " ago", with: "")
    }
}

extension FlightTrackingView {
    /// "4:20 pm your time", or nothing when there is nothing to convert.
    ///
    /// Compared on the offset at *that instant*, not on the identifiers: two zones with different
    /// names can be the same clock on the day in question, and printing "11:20 pm your time" under
    /// "11:20 pm" is noise. It also catches the reverse — one zone on daylight saving and the other
    /// not — which comparing names would miss.
    static func homeTimeLine(for time: Date, airportZone: TimeZone, homeZone: TimeZone) -> String? {
        guard airportZone.secondsFromGMT(for: time) != homeZone.secondsFromGMT(for: time) else { return nil }
        let local = time.formatted(Date.FormatStyle(timeZone: homeZone).day().month(.abbreviated).hour().minute())
        return "\(local) your time"
    }
}
