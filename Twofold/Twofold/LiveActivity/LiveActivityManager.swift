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

    /// Push tokens ActivityKit has handed us that the backend hasn't accepted yet.
    ///
    /// `Activity.pushTokenUpdates` emits a given token exactly once. Registration used to be a
    /// single `try?`-swallowed call inside that loop, so one failed attempt — not yet
    /// authenticated at launch, briefly offline, a transient 5xx — orphaned the Activity
    /// permanently: the backend never learned the token, so it could never push an update or an
    /// end, and the Lock Screen kept whatever content it started with until iOS's own multi-hour
    /// limit. That is exactly the reported failure (a flight showing "departing shortly" an hour
    /// and a half after it landed), and `live_activity_push_tokens` being empty in production
    /// says it was failing for every Activity, not occasionally.
    ///
    /// Holding the token here instead lets `syncActivities` retry on every refresh until it
    /// sticks. Cleared on success and when the Activity ends.
    private var unregisteredTokens: [UUID: (activityID: String, pushToken: String)] = [:]

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

        await retryUnregisteredTokens()

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
    /// `dismissalPolicy: .immediate` rather than `endActivity`'s own shorter-but-not-instant
    /// default: sign-out needs the signed-out account's Live Activity gone from the Lock Screen
    /// right away, not sitting there for another half hour after the person who tracked it is no
    /// longer signed in.
    func endAll() async {
        for (flightID, activity) in runningActivities {
            await endActivity(activity, flightID: flightID, dismissalPolicy: .immediate)
        }
    }

    private func startActivity(for flight: Flight, travelerName: String, isReunion: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = flight.makeJourneyActivityAttributes(travelerName: travelerName)
        let content = ActivityContent(
            state: flight.makeJourneyActivityContentState(isReunion: isReunion),
            staleDate: staleDate(for: flight)
        )
        guard let activity = try? Activity<JourneyActivityAttributes>.request(attributes: attributes, content: content, pushType: .token) else { return }
        runningActivities[flight.id] = activity
        observePushToken(activity, flightID: flight.id)
    }

    private func updateActivity(_ activity: Activity<JourneyActivityAttributes>, for flight: Flight, isReunion: Bool) async {
        let content = ActivityContent(
            state: flight.makeJourneyActivityContentState(isReunion: isReunion),
            staleDate: staleDate(for: flight)
        )
        await activity.update(content)
    }

    /// The default lingers deliberately — a just-landed flight is worth a glance for a few
    /// minutes — but only briefly. `.default` (ActivityKit's own) keeps the ended Activity on the
    /// Lock Screen for up to *four hours*, which on its own is enough for someone to report a
    /// flight that "hasn't disappeared" an hour and a half after arriving, even once the content
    /// is correct. Half an hour is long enough to be useful and short enough not to read as stuck.
    private static let endedDismissalDelay: TimeInterval = 30 * 60

    private func endActivity(
        _ activity: Activity<JourneyActivityAttributes>,
        flightID: UUID,
        dismissalPolicy: ActivityUIDismissalPolicy? = nil
    ) async {
        let policy = dismissalPolicy ?? .after(.now + LiveActivityManager.endedDismissalDelay)
        await activity.end(nil, dismissalPolicy: policy)
        runningActivities.removeValue(forKey: flightID)
        unregisteredTokens.removeValue(forKey: flightID)
        tokenObservationTasks[flightID]?.cancel()
        tokenObservationTasks.removeValue(forKey: flightID)
        try? await AeroFlightService.endLiveActivityToken(activityID: activity.id)
    }

    /// Sends whichever token is outstanding for this flight, clearing it only once the backend
    /// has actually taken it.
    private func registerToken(flightID: UUID) async {
        guard let pending = unregisteredTokens[flightID] else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await AeroFlightService.registerLiveActivityToken(
                flightID: flightID,
                activityID: pending.activityID,
                pushToken: pending.pushToken,
                environment: environment
            )
            unregisteredTokens[flightID] = nil
        } catch {
            // Deliberately kept — the next refresh retries it. Without this the Activity is
            // stranded with no way for the server to ever reach it.
            print("[live-activity] token registration failed for \(flightID), will retry: \(error)")
        }
    }

    private func retryUnregisteredTokens() async {
        for flightID in unregisteredTokens.keys {
            await registerToken(flightID: flightID)
        }
    }

    /// When the content on screen should stop being presented as current.
    ///
    /// Every Activity was previously created with `staleDate: nil`, meaning iOS had no reason to
    /// ever doubt it — a Lock Screen card kept asserting "departing shortly" indefinitely, with
    /// full confidence, long after the flight had landed. A stale date bounds that: past it the
    /// system marks the content stale and the widget can say so (`context.isStale`) instead of
    /// stating something it can no longer stand behind.
    ///
    /// Set to the best-known arrival, falling back to a day past departure when there's no arrival
    /// estimate at all.
    ///
    /// The arrival itself, with no grace period. There used to be thirty minutes of it, to allow
    /// for late arrival reporting — but the stale date is also the only thing that re-renders this
    /// card at a chosen moment, and during that half hour a landed flight kept counting *up* under
    /// the words "Arrives in", because `Text(_, style: .relative)` keeps ticking while the branch
    /// that wrapped it doesn't get re-evaluated. Marking it stale at the arrival closes that window.
    ///
    /// The cost is that a flight whose landing push is a few minutes late briefly says it may be
    /// out of date, then corrects itself when the push lands and resets both the content and this
    /// date. A moment of honest uncertainty is worth more than half an hour of confident nonsense.
    private func staleDate(for flight: Flight) -> Date {
        if let arrival = flight.estimatedIn ?? flight.scheduledIn {
            return arrival
        }
        if let departure = flight.estimatedOut ?? flight.scheduledOut {
            return departure.addingTimeInterval(24 * 60 * 60)
        }
        return Date().addingTimeInterval(12 * 60 * 60)
    }

    #if DEBUG
    /// Test-only access to the rule above. `LiveActivityManager` can't be exercised end to end from
    /// a test — ActivityKit needs a real host — but the date it hands ActivityKit is a pure function
    /// of the flight, and that's the part that was wrong.
    func staleDateForTesting(_ flight: Flight) -> Date { staleDate(for: flight) }
    #endif

    private func observePushToken(_ activity: Activity<JourneyActivityAttributes>, flightID: UUID) {
        tokenObservationTasks[flightID]?.cancel()
        tokenObservationTasks[flightID] = Task {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                unregisteredTokens[flightID] = (activityID: activity.id, pushToken: hex)
                await registerToken(flightID: flightID)
            }
        }
    }
}
