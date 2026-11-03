//
//  FlightTrackingHeader.swift
//  Twofold
//
//  Flight Details' fixed header: airline, route, status pill and countdown, and the key moment in
//  the viewer's own time.
//

import SwiftUI

struct FlightTrackingHeader: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight

    /// Ticks. The countdown and the home-time line used to be worked out once per render, so they
    /// only moved when something unrelated changed, and somebody watching at the gate saw "Departs
    /// in 35m" sit still (FLT-11). Every 30 seconds keeps a minute-resolution countdown honest.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            headerContent(now: context.date)
        }
    }

    /// True when tracking stopped because the flight is done, rather than never having started.
    ///
    /// The two are told apart by the flight itself rather than by anything recorded about it: the
    /// system only ever clears `trackingEnabled` once a flight has reached a terminal state (or
    /// the couple dissolved, or the subscription lapsed — both of which leave a flight that is
    /// also, by then, in the past). An untracked flight still ahead of its departure was never
    /// tracked.
    ///
    /// By the clock as well as the status (`Flight.isOver`): an untracked flight never hears from the
    /// provider, so it is still `.scheduled` after it has flown, and this used to offer to spend a
    /// monthly slot tracking it (FLT-10).
    private var isPastTracking: Bool {
        flight.isOver()
    }

    private func headerContent(now: Date) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            if flight.airlineName != nil || !flight.flightNumberIATA.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    AirlineLogoView(url: flight.displayLogoURL, size: 28)
                    Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            // This header sits outside the ScrollView (see `FlightTrackingView.body`) — permanently on
            // screen, so a wrap here permanently eats vertical space rather than just scrolling
            // past. Capped rather than forced to 1 line since a long route pair is still meant
            // to wrap gracefully at 2 lines, just not unbounded.
            Text("\(flight.origin.displayName) → \(flight.destination.displayName)")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: Theme.Spacing.sm) {
                StatusPill(flight: flight, now: now)
                Text(flight.countdownSummary(at: now))
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier("flight.countdown")
            }

            if flight.faFlightID == nil {
                Text("This flight is on the airline's schedule — we'll start tracking it live automatically once AeroAPI makes it available, usually a few days before departure.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Every time elsewhere on this screen (journey rows, departure/arrival cards) is
            // deliberately shown in *that airport's* local time, which is easy to misread as
            // "my time" and mistake for a bug — this one line anchors the same key moment in
            // the user's own home-city time instead, e.g. "4:30pm (Melbourne time)".
            if let userLocalTimeLabel = userLocalTimeLabel(now: now) {
                Text(userLocalTimeLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            // `trackingEnabled == false` means two different things now, and this line used to
            // assume the first: a flight the system stopped following two hours after it landed.
            // Since the allowance moved onto tracking it also means a flight that was never
            // followed at all — for which "no longer" is wrong and "history is kept for reference"
            // is wronger, because that flight has not happened yet. `FlightNotTrackedCard` says the
            // right thing for that case and offers to fix it, so this stays out of its way.
            if !flight.trackingEnabled, isPastTracking {
                // Explains why pulling to refresh here won't visibly do anything, instead of a
                // spinner that cycles and stops with nothing to show for it.
                Text("No longer being tracked — this flight's history is kept for reference.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The same moment `countdownSummary` counts to (`Flight.countdownMilestone`), so the header's
    /// two lines always describe one instant — one counting down to it, the other anchoring it in
    /// the user's time. This had its own copy of the choice, which put boarding with the arrival
    /// while the countdown beside it counted to the departure (FLT-7).
    private func userLocalTimeLabel(now: Date) -> String? {
        guard let date = flight.countdownMilestone(at: now) else { return nil }
        let timeZone = appModel.currentUser.homeCity?.timeZone ?? .current
        // Date included alongside the time, not just hour:minute — a countdown like "1d 9h"
        // crossing midnight is easy to misjudge against "today" without an explicit day/month
        // to anchor it, which read as the countdown itself being wrong when it wasn't.
        let dateTimeString = date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute().day().month(.abbreviated))
        let offset = TimeMath.utcOffsetLabel(for: timeZone, at: date)
        guard let cityName = appModel.currentUser.homeCity?.city else { return "\(dateTimeString) your time (\(offset))" }
        return "\(dateTimeString) (\(cityName), \(offset))"
    }
}
