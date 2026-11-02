//
//  Flight+LiveActivity.swift
//  Twofold
//
//  Pure mapping from a Flight to the shared JourneyActivityAttributes/ContentState shape —
//  used by LiveActivityManager to start/update Activities, and mirrored server-side (in TS) by
//  supabase/functions/_shared/flight-sync.ts's notifyLiveActivity for push updates. Reuses
//  Flight's own progress/countdownSummary computed properties rather than recomputing them, but
//  deliberately reads `scheduledOut`/`scheduledIn` directly (not the `scheduledDeparture`/
//  `scheduledArrival` computed properties, which fall back to `.now` when unknown).
//

import Foundation
#if canImport(ActivityKit)

/// Who this journey is between, from the point of view of the device showing it.
struct JourneyParticipants {
    let travelerName: String
    let partnerName: String
    let viewerIsTraveler: Bool
}

extension Flight {
    /// Whether `LiveActivityManager` starts a card for this flight: tracked, and at the gate or
    /// later. Unchanged by FLT-3 — when to start one is FLT-4's question, not this one's.
    func startsLiveActivity(at now: Date = .now) -> Bool {
        trackingEnabled && status.isActivelyTracked
    }

    /// How far ahead a delayed departure can be and still keep a running card up.
    static let delayedCardHorizon: TimeInterval = 12 * 60 * 60

    /// Whether a card already running for this flight stays up.
    ///
    /// It used to be the same test as starting one, and `.delayed` isn't actively tracked. The
    /// server only reports `boarding` within its boarding window around the estimated departure;
    /// outside it, a slip of more than five minutes reads `delayed`. So a card that started at
    /// boarding was ended on the next refresh the moment departure slipped — exactly when the person
    /// waiting needs it — and started again later as a new card (FLT-3). A delayed flight keeps its
    /// card while the departure is within `delayedCardHorizon`; the server ends it at a terminal
    /// status, as it always has.
    func keepsLiveActivity(at now: Date = .now) -> Bool {
        if startsLiveActivity(at: now) { return true }
        guard trackingEnabled, !cancelled, status == .delayed, let departure = bestDeparture else { return false }
        return departure.timeIntervalSince(now) < Self.delayedCardHorizon
    }

    func makeJourneyActivityAttributes(participants: JourneyParticipants, homeTimeZone: TimeZone) -> JourneyActivityAttributes {
        JourneyActivityAttributes(
            flightID: id,
            travelerName: participants.travelerName,
            partnerName: participants.partnerName,
            viewerIsTraveler: participants.viewerIsTraveler,
            flightNumber: displayNumber,
            airlineName: airlineName,
            originCode: origin.displayCode,
            originCity: origin.city,
            destinationCode: destination.displayCode,
            destinationCity: destination.city,
            // Each airport's own zone, home's when that isn't known — the tracking screen's rule
            // (FLT-5), decided here so the extension never has to.
            originTimeZoneID: (origin.timeZone ?? homeTimeZone).identifier,
            destinationTimeZoneID: (destination.timeZone ?? homeTimeZone).identifier
        )
    }

    func makeJourneyActivityContentState(isReunion: Bool) -> JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            status: status.rawValue,
            progress: progress,
            isReunion: isReunion,
            // Raw optionals, not the fabricating `scheduledDeparture`/`scheduledArrival`
            // computed properties (those fall back to `.now` when unknown) — see
            // `JourneyActivityAttributes.ContentState`'s doc comment.
            scheduledDeparture: scheduledOut,
            scheduledArrival: scheduledIn,
            estimatedDeparture: estimatedOut,
            estimatedArrival: estimatedIn,
            actualDeparture: actualOut,
            actualArrival: actualIn,
            gateOrigin: gateOrigin,
            gateDestination: gateDestination,
            terminalOrigin: terminalOrigin,
            terminalDestination: terminalDestination,
            baggageClaim: baggageClaim,
            departureDelayMinutes: departureDelaySeconds.map { $0 / 60 },
            arrivalDelayMinutes: arrivalDelaySeconds.map { $0 / 60 }
        )
    }
}
#endif
