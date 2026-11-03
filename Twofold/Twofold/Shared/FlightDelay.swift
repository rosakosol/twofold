//
//  FlightDelay.swift
//  Twofold
//
//  What counts as delayed, decided once.
//
//  Three thresholds used to disagree: the status pill said "Delayed 10 min" (more than five
//  minutes), the departure card underneath said "On time" (anything under fifteen), and the share
//  sticker said on time too (fifteen or more). Same screen, same flight, opposite answers (FLT-13).
//  Now every live reading — pill, card caption, widget badge, sticker — uses the server's own rule,
//  `DELAY_THRESHOLD_SECONDS` in supabase/functions/_shared/flight-status.ts, which is also what
//  turns a flight's status to `delayed`.
//
//  The fifteen-minute window is a different thing with a different name: the industry's on-time
//  performance bucket, which the 60-day delay stats are reported against. It describes a flight
//  number's history, not whether this flight is late.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for that
//  target in project.pbxproj).
//

import Foundation

nonisolated enum FlightDelay {
    /// More than this is delayed. Matches the server's `DELAY_THRESHOLD_SECONDS`.
    static let thresholdSeconds = 300

    /// How far a time ran from its schedule, in the terms the departure and arrival cards print.
    enum Deviation: Equatable {
        case early(minutes: Int)
        case onTime
        case late(minutes: Int)
    }

    static func isDelayed(seconds: Int?) -> Bool { (seconds ?? 0) > thresholdSeconds }

    /// Whole minutes late, or nil when it isn't late enough to say so.
    static func delayedMinutes(seconds: Int?) -> Int? {
        guard let seconds, isDelayed(seconds: seconds) else { return nil }
        return seconds / 60
    }

    /// Early by a minute or more, late by more than the threshold, otherwise on time.
    static func deviation(scheduled: Date?, actualOrEstimated: Date?) -> Deviation? {
        guard let scheduled, let actualOrEstimated else { return nil }
        let seconds = Int(actualOrEstimated.timeIntervalSince(scheduled).rounded())
        if seconds <= -60 { return .early(minutes: Int((Double(-seconds) / 60).rounded())) }
        if isDelayed(seconds: seconds) { return .late(minutes: Int((Double(seconds) / 60).rounded())) }
        return .onTime
    }
}
