//
//  JourneyTimeRemainingText.swift
//  LiveActivities
//
//  A real date-anchored `Text`, not a pre-formatted string — mirrors `computeTimeRemainingLabel`
//  (server, supabase/functions/_shared/flight-sync.ts) and `Flight.countdownSummary` (Swift,
//  main app) in *wording*, but ticks live on-device instead of needing a fresh push for every
//  minute that passes.
//
//  `Text(_, style: .relative)` counts *up* once its date passes, and the branch that wrapped it in
//  "Arrives in…" was chosen at render time and never re-evaluated — so a landed flight sat there
//  reading "Arrives in 5 minutes", the 5 minutes growing, for as long as nothing re-rendered it.
//  What re-renders it at the right instant is the content's stale date; see
//  `LiveActivityManager.staleDate`, which is set to the arrival for exactly this reason.
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

/// A live countdown to `date` in whole minutes, hours and days — "52 minutes", "1 hour, 7
/// minutes" — that ticks on the system clock like `Text(_, style: .relative)` but without that
/// style's seconds. "52 min., 52 sec." changed width every second and was the longest thing in the
/// island and the Lock Screen card, so it cut off the headline beside it. `maxFieldCount: 1` is
/// for the compact island, where "2 hours" is as much as fits.
func journeyCountdownText(to date: Date, maxFieldCount: Int = 2) -> Text {
    Text(.currentDate, format: .offset(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: maxFieldCount, sign: .never))
}

/// "Arrives in 52 minutes", "Departs in 2 hours" — or, with `compact`, just the figure, for the
/// compact island's trailing slot where the avatar beside it already says whose flight it is.
@ViewBuilder
func journeyTimeRemainingText(_ state: JourneyActivityAttributes.ContentState, compact: Bool = false) -> some View {
    let status = FlightStatus(rawValue: state.status)
    switch status {
    case .cancelled:
        Text("Cancelled")
    case .diverted:
        Text("Diverted")
    case .landed, .arrived:
        if let arrival = state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival {
            if compact {
                Text("Landed")
            } else {
                Text("Arrived \(journeyCountdownText(to: arrival)) ago")
            }
        } else {
            Text("Arrived")
        }
    case .landingSoon, .inAir, .departed:
        // "boarding" deliberately excluded here — still at the gate, not yet departed, so it
        // falls through to the departure countdown below instead of showing "Arrives in…" for a
        // flight that hasn't taken off yet (same reasoning as the server/main-app mirrors).
        if let arrival = state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival {
            if arrival > .now {
                if compact {
                    journeyCountdownText(to: arrival, maxFieldCount: 1)
                } else {
                    Text("Arrives in \(journeyCountdownText(to: arrival))")
                }
            } else {
                // Airborne by the last thing we heard, but the arrival time has passed and nothing
                // has confirmed the landing. It fell through to the departure fallback here, which
                // announced "Departing shortly" for a flight that had been in the air for hours.
                Text("Landing")
            }
        } else {
            departureFallbackText(state, compact: compact)
        }
    default:
        departureFallbackText(state, compact: compact)
    }
}

@ViewBuilder
private func departureFallbackText(_ state: JourneyActivityAttributes.ContentState, compact: Bool) -> some View {
    if let departure = state.actualDeparture ?? state.estimatedDeparture ?? state.scheduledDeparture {
        if departure > .now {
            if compact {
                journeyCountdownText(to: departure, maxFieldCount: 1)
            } else {
                Text("Departs in \(journeyCountdownText(to: departure))")
            }
        } else {
            Text("Departing shortly")
        }
    } else {
        Text(state.status.capitalized)
    }
}
