//
//  JourneyTimeRemainingText.swift
//  LiveActivities
//
//  A real date-anchored `Text`, not a pre-formatted string — mirrors `computeTimeRemainingLabel`
//  (server, supabase/functions/_shared/flight-sync.ts) and `Flight.countdownSummary` (Swift,
//  main app) in *wording*, but ticks live on-device instead of needing a fresh push for every
//  minute that passes.
//
//  The old `ContentState.timeRemainingLabel` was a plain string set once per push, and a push
//  only fires on a genuinely relevant change (see `isLiveActivityRelevantChange` in
//  flight-sync.ts — a discrete field change, or the estimate drifting >10 minutes) — for a flight
//  running smoothly on schedule, that can mean the entire flight. The countdown obviously keeps
//  ticking down every minute regardless of whether anything else changed, so anchoring it to a
//  real `Date` via `Text(_:style:)` (a small set of SwiftUI primitives WidgetKit/ActivityKit
//  specifically re-render on a system clock, independent of push cadence) fixes that at the
//  source instead of needing to push more often.
//

import SwiftUI

@ViewBuilder
func journeyTimeRemainingText(_ state: JourneyActivityAttributes.ContentState) -> some View {
    let status = FlightStatus(rawValue: state.status)
    switch status {
    case .cancelled:
        Text("Cancelled")
    case .diverted:
        Text("Diverted")
    case .landed, .arrived:
        if let arrival = state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival {
            Text("Arrived \(arrival, style: .relative) ago")
        } else {
            Text("Arrived")
        }
    case .landingSoon, .inAir, .departed:
        // "boarding" deliberately excluded here — still at the gate, not yet departed, so it
        // falls through to the departure countdown below instead of showing "Arrives in…" for a
        // flight that hasn't taken off yet (same reasoning as the server/main-app mirrors).
        if let arrival = state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival, arrival > .now {
            Text("Arrives in \(arrival, style: .relative)")
        } else {
            departureFallbackText(state)
        }
    default:
        departureFallbackText(state)
    }
}

@ViewBuilder
private func departureFallbackText(_ state: JourneyActivityAttributes.ContentState) -> some View {
    if let departure = state.actualDeparture ?? state.estimatedDeparture ?? state.scheduledDeparture {
        if departure > .now {
            Text("Departs in \(departure, style: .relative)")
        } else {
            Text("Departing shortly")
        }
    } else {
        Text(state.status.capitalized)
    }
}
