//
//  Flight+LiveActivity.swift
//  Twofold
//
//  Pure mapping from a Flight to the shared JourneyActivityAttributes/ContentState shape —
//  used by LiveActivityManager to start/update Activities, and mirrored server-side (in TS) by
//  supabase/functions/_shared/flight-sync.ts's notifyLiveActivity for push updates. Reuses
//  Flight's own progress/countdownSummary/scheduledDeparture/scheduledArrival computed
//  properties rather than recomputing them.
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
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
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
