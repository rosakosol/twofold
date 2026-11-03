//
//  FlightPortCards.swift
//  Twofold
//
//  Flight Details' Departure and Arrival cards, and the label/value row the screen's detail cards
//  share.
//

import SwiftUI

struct FlightDepartureCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight

    private var homeTimeZone: TimeZone { appModel.currentUser.homeCity?.timeZone ?? .current }

    var body: some View {
        SectionCard {
            FlightPortCard.header(icon: "airplane.departure", title: "Departure", code: flight.origin.displayCode, city: flight.origin.displayName)
            Text("All times shown in local time").font(.caption2).foregroundStyle(Theme.textSecondary)
            FlightDetailRow(label: "Scheduled", value: FlightPortCard.timeOrNA(flight.scheduledOut, timeZone: flight.origin.timeZone, fallback: homeTimeZone))
            FlightDetailRow(label: flight.actualOut != nil ? "Actual" : "Estimated", value: FlightPortCard.timeOrNA(flight.actualOut ?? flight.estimatedOut, timeZone: flight.origin.timeZone, fallback: homeTimeZone))
            if let delta = FlightPortCard.delayDelta(scheduled: flight.scheduledOut, actualOrEstimated: flight.actualOut ?? flight.estimatedOut) {
                FlightPortCard.delayDeltaCaption(delta)
            }
            FlightDetailRow(label: "Terminal", value: flight.terminalOrigin ?? "Not available")
            FlightDetailRow(label: "Gate", value: flight.gateOrigin ?? "Not available")
        }
    }
}

struct FlightArrivalCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight

    private var homeTimeZone: TimeZone { appModel.currentUser.homeCity?.timeZone ?? .current }

    var body: some View {
        SectionCard {
            FlightPortCard.header(icon: "airplane.arrival", title: "Arrival", code: flight.destination.displayCode, city: flight.destination.displayName)
            Text("All times shown in local time").font(.caption2).foregroundStyle(Theme.textSecondary)
            FlightDetailRow(label: "Scheduled", value: FlightPortCard.timeOrNA(flight.scheduledIn, timeZone: flight.destination.timeZone, fallback: homeTimeZone))
            FlightDetailRow(label: flight.actualIn != nil ? "Actual" : "Estimated", value: FlightPortCard.timeOrNA(flight.actualIn ?? flight.estimatedIn, timeZone: flight.destination.timeZone, fallback: homeTimeZone))
            if let delta = FlightPortCard.delayDelta(scheduled: flight.scheduledIn, actualOrEstimated: flight.actualIn ?? flight.estimatedIn) {
                FlightPortCard.delayDeltaCaption(delta)
            }
            FlightDetailRow(label: "Terminal", value: flight.terminalDestination ?? "Not available")
            FlightDetailRow(label: "Gate", value: flight.gateDestination ?? "Not available")
            FlightDetailRow(label: "Baggage claim", value: flight.baggageClaim ?? "Not available")
        }
    }
}

/// What the two cards share: the header, the delay caption and the time formatting.
enum FlightPortCard {
    /// Port/city used to live buried in an "Airport" detail row below; pulled up here, inline
    /// with the card's own title and a departing/arriving plane glyph, so it reads at a glance
    /// instead of requiring a scan down the row list.
    static func header(icon: String, title: String, code: String, city: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(code) · \(city)").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    struct DelayDelta {
        let text: String
        let color: Color
    }

    /// `FlightDelay`'s threshold, the one the status pill above uses. This used to borrow the
    /// fifteen-minute on-time-performance bucket from the delay stats, so a flight ten minutes late
    /// read "Delayed 10 min" in the pill and "On time" here (FLT-13). That bucket describes a flight
    /// number's history; this is whether this flight is late.
    static func delayDelta(scheduled: Date?, actualOrEstimated: Date?) -> DelayDelta? {
        switch FlightDelay.deviation(scheduled: scheduled, actualOrEstimated: actualOrEstimated) {
        case nil: return nil
        case .early(let minutes): return DelayDelta(text: "\(minutes) min early", color: Theme.success)
        case .onTime: return DelayDelta(text: "On time", color: Theme.success)
        case .late(let minutes): return DelayDelta(text: "+\(minutes) min", color: Theme.warning)
        }
    }

    static func delayDeltaCaption(_ delta: DelayDelta) -> some View {
        HStack {
            Spacer()
            Text(delta.text).font(.caption2.weight(.semibold)).foregroundStyle(delta.color)
        }
    }

    /// `fallback` rather than `.current`: callers pass the user's home zone, so an airport whose
    /// own timezone we do not know reads in the same frame as the rest of the screen instead of in
    /// whatever zone the phone happens to be set to.
    static func timeOrNA(_ date: Date?, timeZone: TimeZone?, fallback: TimeZone) -> String {
        guard let date else { return "Not available" }
        return date.formatted(Date.FormatStyle(timeZone: timeZone ?? fallback).hour().minute().day().month(.abbreviated))
    }
}

/// One label/value line of a Flight Details card, with "Not available" drawn quietly.
struct FlightDetailRow: View {
    let label: String
    let value: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        let isUnavailable = value == "Not available"
        return HStack {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(isUnavailable ? .regular : .medium))
                .foregroundStyle(isUnavailable ? Theme.textSecondary : tint)
        }
    }
}
