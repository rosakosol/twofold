//
//  LiveActivityManager.swift
//  Twofold
//
//  Owns the app's ActivityKit lifecycle for flight-tracking Live Activities — starts/updates/
//  ends them locally as an immediate-feedback path, and forwards each Activity's push token to
//  the backend so supabase/functions/_shared/flight-sync.ts can push content-state updates even
//  while the app is backgrounded (see sendLiveActivityUpdate in apns.ts). Local updates and
//  server pushes are complementary, not redundant — local updates land instantly when the app
//  is open; pushes are what keeps the Lock Screen/Dynamic Island fresh the rest of the time.
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var runningActivities: [UUID: Activity<JourneyActivityAttributes>] = [:]
    private var tokenObservationTasks: [UUID: Task<Void, Never>] = [:]
    private var hasReconciledLaunch = false

    private init() {}

    /// Called at the end of every `AppModel.refreshFlights()` — starts activities for newly
    /// trackable flights, updates ones already running, ends ones that became inactive or
    /// disappeared from the list entirely.
    func syncActivities(for flights: [Flight], travelerName: (Flight) -> String, isReunion: (Flight) -> Bool) async {
        for flight in flights {
            let shouldTrack = flight.trackingEnabled && flight.status.isActivelyTracked
            if let activity = runningActivities[flight.id] {
                if shouldTrack {
                    await updateActivity(activity, for: flight, isReunion: isReunion(flight))
                } else {
                    await endActivity(activity, flightID: flight.id)
                }
            } else if shouldTrack {
                await startActivity(for: flight, travelerName: travelerName(flight), isReunion: isReunion(flight))
            }
        }

        let flightIDs = Set(flights.map(\.id))
        let orphanedIDs = runningActivities.keys.filter { !flightIDs.contains($0) }
        for flightID in orphanedIDs {
            guard let activity = runningActivities[flightID] else { continue }
            await endActivity(activity, flightID: flightID)
        }
    }

    /// Reconciles this manager's bookkeeping against ActivityKit's own `Activity.activities`
    /// list — `Activity` instances survive app relaunch, but this manager's tracking dictionary
    /// and push-token observation tasks don't. Self-guarding (only does real work once per
    /// process) so it's safe to call from every `AppModel.refreshFlights()` rather than needing
    /// a dedicated launch hook.
    func reconcileOnLaunch(with flights: [Flight]) async {
        guard !hasReconciledLaunch else { return }
        hasReconciledLaunch = true

        for activity in Activity<JourneyActivityAttributes>.activities {
            guard let flight = flights.first(where: { $0.id == activity.attributes.flightID }) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            runningActivities[flight.id] = activity
            observePushToken(activity, flightID: flight.id)
            if !(flight.trackingEnabled && flight.status.isActivelyTracked) {
                await endActivity(activity, flightID: flight.id)
            }
        }
    }

    /// Called on sign-out — ends every Live Activity this device is currently running, so the
    /// Lock Screen/Dynamic Island don't keep showing the signed-out account's flight after
    /// sign-out. Reuses `endActivity`'s own teardown (local end, bookkeeping cleanup, and
    /// unregistering the server-side push token) for each one still running, but with
    /// `dismissalPolicy: .immediate` — `endActivity`'s own default (`.default`) tells the system
    /// to keep showing the activity's final content for up to 4 hours, which is exactly right for
    /// "flight landed" but is precisely what must *not* happen here: sign-out needs the
    /// signed-out account's Live Activity gone from the Lock Screen right away, not lingering for
    /// hours after the person who tracked it is no longer signed in.
    func endAll() async {
        for (flightID, activity) in runningActivities {
            await endActivity(activity, flightID: flightID, dismissalPolicy: .immediate)
        }
    }

    private func startActivity(for flight: Flight, travelerName: String, isReunion: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = flight.makeJourneyActivityAttributes(travelerName: travelerName)
        let content = ActivityContent(state: flight.makeJourneyActivityContentState(isReunion: isReunion), staleDate: nil)
        guard let activity = try? Activity<JourneyActivityAttributes>.request(attributes: attributes, content: content, pushType: .token) else { return }
        runningActivities[flight.id] = activity
        observePushToken(activity, flightID: flight.id)
    }

    private func updateActivity(_ activity: Activity<JourneyActivityAttributes>, for flight: Flight, isReunion: Bool) async {
        let content = ActivityContent(state: flight.makeJourneyActivityContentState(isReunion: isReunion), staleDate: nil)
        await activity.update(content)
    }

    private func endActivity(_ activity: Activity<JourneyActivityAttributes>, flightID: UUID, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        await activity.end(nil, dismissalPolicy: dismissalPolicy)
        runningActivities.removeValue(forKey: flightID)
        tokenObservationTasks[flightID]?.cancel()
        tokenObservationTasks.removeValue(forKey: flightID)
        try? await AeroFlightService.endLiveActivityToken(activityID: activity.id)
    }

    private func observePushToken(_ activity: Activity<JourneyActivityAttributes>, flightID: UUID) {
        tokenObservationTasks[flightID]?.cancel()
        tokenObservationTasks[flightID] = Task {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                #if DEBUG
                let environment = "sandbox"
                #else
                let environment = "production"
                #endif
                try? await AeroFlightService.registerLiveActivityToken(
                    flightID: flightID,
                    activityID: activity.id,
                    pushToken: hex,
                    environment: environment
                )
            }
        }
    }
}
