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

extension Flight {
    func makeJourneyActivityAttributes(travelerName: String) -> JourneyActivityAttributes {
        JourneyActivityAttributes(
            flightID: id,
            travelerName: travelerName,
            flightNumber: displayNumber,
            airlineName: airlineName,
            originCode: origin.displayCode,
            originCity: origin.city,
            destinationCode: destination.displayCode,
            destinationCity: destination.city
        )
    }

    func makeJourneyActivityContentState(isReunion: Bool) -> JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            status: status.rawValue,
            progress: progress,
            timeRemainingLabel: countdownSummary,
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
            arrivalDelayMinutes: arrivalDelaySeconds.map { $0 / 60 },
            lastUpdatedAt: .now
        )
    }
}
#endif
