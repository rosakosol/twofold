//
//  AppModel.swift
//  Twofold
//
//  Root store backed by Supabase. `couple`/`trips`/`memories` are loaded from the backend
//  once a session exists.
//

import Foundation
import Observation
import PostHog
import RevenueCat
import Supabase
import UserNotifications
import WidgetKit

@Observable
final class AppModel {
    var isLoadingSession = true
    var hasCouple: Bool = false
    /// Set by `loadSignedInState()` when it finds a session belonging to an already-deleted
    /// account and signs it back out. `SignInView`/`WelcomeView` read this once to show the
    /// user why they landed back at sign-in instead of their previous session resuming.
    var accountDeletedMessage: String?
    /// Set by `adoptSoloProfile(_:)` whenever it fires while the couple was still considered
    /// connected a moment ago — a partner removing you, or a partner deleting their own account,
    /// look identical from here. `HomeView` reads this once to explain why Trips/Memories/
    /// Flights just went quiet, instead of letting them silently empty out with no context.
    var partnerDisconnectedMessage: String?
    var couple: Couple = AppModel.placeholderCouple
    var trips: [Trip] = []
    var memories: [Memory] = []
    /// Every flight for the couple, independent of trip linkage — the authoritative list.
    /// See `Trip.flight` for the trip-scoped mirror kept for backward-compat UI.
    var flights: [Flight] = []
    /// Home-screen drawing pads — only meaningful once paired, since there's no partner pad to
    /// compare against (and nowhere real to save to) before then.
    var myDrawingURL: URL?
    var partnerDrawingURL: URL?

    /// "Your partner doesn't pay anything" — true if *either* partner's device last reported
    /// an active local StoreKit entitlement (see `BackendService.fetchSubscriptionActive`).
    /// `RootView` gates all of `MainTabView` behind this once `hasCouple` is true.
    var isSubscriptionActive = false
    /// "plus"/"premium", the higher of the two partners' tiers — nil for pre-existing
    /// subscribers from before this column existed (`start_game_session` treats that the same
    /// as "plus" server-side, so this being nil never actually locks anyone out of content).
    var subscriptionTier: String?

    /// Server-persisted "seen it" flags — deliberately not UserDefaults/@AppStorage, since those
    /// live in the app's local sandbox and get wiped on every uninstall/reinstall, showing these
    /// one-time prompts again even though nothing about the account changed. See
    /// `markPartnerConnectedCelebrationShown()`/`dismissSetupChecklist()`.
    var partnerConnectedCelebrationShown = false
    var setupChecklistDismissed = false

    /// Daily Activity streak — see `startOrResumeDailyQuestion()`/`refreshDailyStreak()`. Nil
    /// until the first fetch resolves (not defaulted to 0) so `DailyActivityCard` can show a
    /// placeholder instead of visibly flashing "Start a streak" before the real value loads.
    var dailyStreak: Int?
    var longestDailyStreak: Int?
    /// The instant the daily question/streak next rolls over — real local midnight, resolved
    /// server-side (see `BackendService.fetchDailyStreak`). Nil until the first fetch lands.
    var dailyStreakResetsAt: Date?
    /// Whether a streak that just ended can still be bought back, and what it was worth. Nil until
    /// looked up and left nil when the lookup fails — no offer is better than a wrong one.
    var streakRepair: BackendService.StreakRepairState?
    /// Today's Daily Activity session id, once known (fetched lazily, not at launch — see
    /// `startOrResumeDailyQuestion()`).
    var todaysDailySessionID: UUID?
    /// The actual discussion topic text for today's session — shown on `DailyActivityCard`
    /// instead of a generic teaser line. Nil while loading or if the fetch fails.
    var todaysDailyQuestionText: String?
    /// True while `startOrResumeDailyQuestion()` is in flight.
    ///
    /// `todaysDailyQuestionText == nil` can't stand in for this: it's ambiguous, covering both
    /// "hasn't been fetched yet" and "the fetch finished but the topic couldn't be resolved" (the
    /// inner `try?` in that method). `DailyActivityCard` has to tell those apart — the first
    /// deserves a skeleton, the second deserves the generic teaser rather than a placeholder that
    /// never resolves.
    private(set) var isLoadingDailyQuestion = false
    /// Per-partner completion for today's question — drives the checkmark on each avatar in
    /// `DailyActivityCard`. See `get_daily_question_status` for why this needs its own
    /// RLS-bypassing RPC rather than reading `game_responses` directly.
    var todaysMyAnswered = false
    var todaysPartnerAnswered = false
    /// Set when `startOrResumeDailyQuestion()` fails to obtain a session id — lets
    /// `DailyActivityCard` show a real error state instead of spinning forever on a
    /// `ProgressView` that's silently waiting on data that will never arrive.
    var dailyQuestionError: String?

    /// All active decks + which ones this couple has started, cached after first load
    /// (`loadGameDecksIfNeeded()`) — powers the Games hub's topic list and progress bars. Not
    /// loaded at app launch; only Games-hub visits need it.
    private(set) var gameDecks: [GameDeck]?
    /// True once a deck fetch has been attempted and failed — see `refreshGameDecks`.
    private(set) var gameDecksUnavailable = false
    /// Per-deck completion counts for the couple — see `DeckProgress`/`get_deck_progress()`.
    /// Superseded `playedDeckIDs` (a deck has progress here the moment either partner starts it).
    private(set) var deckProgress: [UUID: DeckProgress]?

    /// Whether the partner has actually redeemed an invite and joined — confirmed by the
    /// backend (an active `couples` row exists), not assumed the moment a code is shared.
    var partnerConnected: Bool = false
    var inviteCode: String?
    /// Incoming "someone wants to connect" requests awaiting my decision (I'm the inviter on
    /// each of these) — see `refreshPendingConnectionRequests()`/`respondToConnectionRequest(_:accept:)`.
    var pendingConnectionRequests: [BackendService.PendingConnectionRequest] = []
    /// My own outgoing request, if I redeemed a code and I'm still waiting on the inviter's
    /// decision — see `refreshPendingOutgoingConnectionRequest()`. `RootView` lets this bypass
    /// the forced re-subscribe paywall entirely (straight into `MainTabView`) for someone who
    /// isn't really solo, just not accepted yet; `HomeView` shows a persistent card for it, with
    /// the option to nudge the inviter — see `sendConnectionRequestReminder()`.
    var pendingOutgoingConnectionRequest: BackendService.OutgoingConnectionRequest?
    /// Whether `pendingOutgoingConnectionRequest` has been looked up yet this session.
    ///
    /// `nil` on that property means two different things — "there is no pending request" and "we
    /// have not asked yet" — and the paywall gate has to tell them apart. Someone who redeemed an
    /// invite and is waiting on the inviter must never be shown a paywall, and at launch the
    /// lookup is a network round trip that lands well after `hasCouple` flips true. Without this,
    /// the gate evaluated during that window and flashed the paywall at exactly the person it is
    /// meant to exempt.
    private(set) var hasResolvedOutgoingConnectionRequest = false

    /// Non-nil only while there's an unacknowledged "your subscription lapsed because {name}
    /// left" notice — set by `adoptSoloProfile(_:)` from `leave_couple`'s server-captured
    /// snapshot (the ex-partner's name is already gone from `partner_name` by the time this
    /// loads). `RootView` shows `SubscriptionLapsedFromDisconnectView` in place of the generic
    /// non-dismissable paywall while this is set — see `markPartnerSubscriptionLapseAcknowledged()`.
    var partnerSubscriptionLapsedPartnerName: String?

    /// Set whenever a newly-crossed, not-yet-shown review milestone is detected — RootView
    /// presents `ReviewPromptView` as a sheet whenever this is non-nil. See
    /// `checkReviewMilestones()`/`noteReviewMilestone(_:)`.
    var pendingReviewMilestone: ReviewMilestone?

    /// RootView presents `PartnerInviteNudgeView` as a sheet whenever this is true — see
    /// `noteSoloActionCompleted()`.
    var pendingPartnerInviteNudge = false

    /// Set once a real `couples` row exists for this user.
    private var backendCoupleID: UUID?
    /// Kept alive for as long as a couple is loaded (started in `adopt`, torn down whenever
    /// `backendCoupleID` is cleared) — without this, `flights` only ever learned about a
    /// server-side change (a landed flight the cron just archived, a new flight the partner
    /// added) when some specific view happened to call `refreshFlights()` itself. A flight the
    /// server had already correctly marked done kept showing as "tracked" on Home/Trips
    /// indefinitely if the app just sat open, only catching up once the user happened to open
    /// that flight's own detail screen (which has its own, single-flight realtime subscription).
    private var flightsRealtimeChannel: RealtimeChannelV2?
    private var flightsRealtimeTask: Task<Void, Never>?
    /// Which couple the current `flightsRealtimeChannel` (if any) belongs to — lets
    /// `startFlightsRealtimeSubscription` skip re-subscribing when nothing actually changed
    /// (see its own doc comment for why that matters, not just as an optimization).
    private var flightsRealtimeCoupleID: UUID?
    /// Trips/memories added locally before pairing completed (no couple to attach them to
    /// yet). Flushed to the backend the moment a real couple shows up.
    private var pendingTripIDs: Set<Trip.ID> = []
    private var pendingMemoryIDs: Set<Memory.ID> = []
    /// A real AeroAPI-resolved flight picked while adding a trip pre-pairing — `addTrip`'s
    /// caller can't attach it via `AeroFlightService.addFlight` yet, since the trip it belongs
    /// to doesn't exist server-side until pairing completes. Kept here (not just as local
    /// `@State` on the view) so it survives past that screen and gets attempted once the trip
    /// is actually inserted, in `performAdopt(_:)` — previously this was silently dropped.
    private var pendingFlightCandidates: [Trip.ID: (candidates: [AeroFlightCandidate], travelerIDs: [Person.ID])] = [:]
    /// A pending memory's photos can't be uploaded until there's a real couple to namespace the
    /// storage path under — held here so they aren't silently dropped, and uploaded once paired.
    private var pendingMemoryPhotoData: [Memory.ID: [Data]] = [:]
    /// Serializes `adopt(_:)` — it can legitimately be entered from three places (launch's
    /// `loadSignedInState`, onboarding's `applyOnboardingAccount`, and Home's
    /// `refreshCoupleStateIfNeeded`, itself fired from both `.onAppear` and
    /// `.onChange(of: scenePhase)`), and `hasCouple` flips true partway through the function body
    /// — so a second call can start while the first is still mid-flight. Without this, two
    /// interleaved calls can both capture the same pending trip/memory before either writes back,
    /// double-inserting it server-side and leaving a duplicate local copy.
    private var inFlightAdopt: Task<Void, Never>?

    /// Optimistic edits to `flights`/`trips`/`memories` still awaiting their network write.
    /// `refreshFlights()`/`refreshTrips()`/`refreshMemories()` each do a full overwrite of their
    /// array from the server — and any of them can run concurrently with one of these writes,
    /// since they're also triggered independently by the couple-wide flights realtime
    /// subscription and by Home's own tab-switch/foreground refresh. A refresh landing in that
    /// window fetches server state that doesn't reflect the write yet, silently reverting the
    /// edit (e.g. an unlinked flight looking linked again) until the next refresh happens to
    /// catch up. Re-applied after every full-array overwrite until the write they belong to
    /// finishes — same fix as the one already in `GameSessionStore.refresh()`.
    private var inFlightMutations: [UUID: () -> Void] = [:]

    private func trackInFlightMutation(_ reapply: @escaping () -> Void) -> UUID {
        let id = UUID()
        inFlightMutations[id] = reapply
        return id
    }

    private func clearInFlightMutation(_ id: UUID) {
        inFlightMutations.removeValue(forKey: id)
    }

    private func reapplyInFlightMutations() {
        for reapply in inFlightMutations.values {
            reapply()
        }
    }

    var currentUser: Person { couple.partnerA }
    var partner: Person { couple.partnerB }

    var needsPartnerInvite: Bool { !partnerConnected }
    var needsFirstTrip: Bool { trips.isEmpty }
    var needsFirstFlight: Bool { !trips.contains { !$0.flights.isEmpty } }
    var needsHomeCities: Bool { couple.partnerA.homeCity == nil || couple.partnerB.homeCity == nil }

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    /// The couple's relevant tracked flights for the Home carousel — whichever are currently in
    /// progress, haven't departed yet, or landed within the last 15 minutes (see
    /// `Flight.isCurrentlyRelevant`), in-progress flights first, then soonest departure first.
    /// Cancelled flights are excluded (nothing useful to show live for those). In-progress always
    /// wins the primary sort (not just a `bestDeparture` tiebreak) since `bestDeparture` prefers
    /// `actualOut`, which can lag null for a flight that has genuinely already left (confirmed
    /// live server-side for FJ810 — see resolve-flight's `isFlightInProgress`) — falling back to a
    /// stale future `scheduledOut` would otherwise sort that flight after one merely upcoming.
    var activeOrUpcomingFlights: [Flight] {
        let relevant = flights.filter { !$0.cancelled && $0.isCurrentlyRelevant }
        return relevant.sorted { lhs, rhs in
            if lhs.status.isActivelyTracked != rhs.status.isActivelyTracked {
                return lhs.status.isActivelyTracked
            }
            return (lhs.bestDeparture ?? .distantFuture) < (rhs.bestDeparture ?? .distantFuture)
        }
    }

    /// Convenience for call sites that only ever cared about the single most relevant flight.
    var activeOrUpcomingFlight: Flight? { activeOrUpcomingFlights.first }

    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming || $0.isActive }.sorted { $0.departureDate < $1.departureDate }
    }

    var pastTrips: [Trip] {
        trips.filter { !$0.isUpcoming && !$0.isActive }.sorted { $0.departureDate > $1.departureDate }
    }

    /// Every flight *not* in `activeOrUpcomingFlights` — trip-linked or not, for the Trips
    /// screen's "Flights" tab, which surfaces every flight that's ever been added rather than
    /// just untethered ones. Most recent first.
    var completedFlights: [Flight] {
        let activeIDs = Set(activeOrUpcomingFlights.map(\.id))
        return flights.filter { !activeIDs.contains($0.id) }
            .sorted { ($0.bestArrival ?? $0.scheduledArrival) > ($1.bestArrival ?? $1.scheduledArrival) }
    }

    var stats: MockData.RelationshipStats {
        // Reunion-only — this feeds the "you've travelled X for each other" hero (PassportView,
        // SnapshotThemeCard), which should only count trips actually taken to see each other, not
        // every trip ever logged (a solo/personal trip isn't "for each other" just because it
        // happened). `FlightStats.totalDistanceKm` is the separate, deliberately-unfiltered "every
        // flight regardless of reason" figure shown in the Flight Distance breakdown.
        // `effectiveDistanceKm` (not the raw `distanceKm`) so a connecting itinerary's real
        // flown distance counts, not just the trip's direct origin→destination distance.
        let totalDistance = trips.filter { $0.category == .reunion }.reduce(0) { $0 + $1.effectiveDistanceKm }
        let daysTogether = max(0, Calendar.current.dateComponents([.day], from: couple.startedDatingOn, to: .now).day ?? 0)
        return MockData.RelationshipStats(
            totalDistanceKm: totalDistance,
            tripCount: trips.count,
            flightCount: trips.filter { !$0.flights.isEmpty }.count,
            countryCount: Set(trips.flatMap { [$0.origin.country, $0.destination.country] }).count,
            daysTogether: daysTogether,
            earthMultiple: totalDistance / Geo.earthCircumferenceKm
        )
    }

    var nextReunionDaysToGo: Int {
        guard let trip = upcomingTrips.first else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    func memories(in place: Place) -> [Memory] {
        memories.filter { $0.place?.id == place.id }
    }

    var citiesWithMemories: [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard let place = memory.place, !seen.contains(place.id) else { return nil }
            seen.insert(place.id)
            return place
        }
    }

    // MARK: - Session / backend sync

    /// Called once at launch. Restores a session if one exists and loads real state; leaves
    /// `hasCouple = false` only when there's genuinely no session, so `RootView` routes into
    /// onboarding for a first-time user but never for a returning one who just hasn't paired
    /// with a partner yet (see `loadSignedInState`).
    func restoreSession() async {
        defer { isLoadingSession = false }

        // Cache first, always — not only when we already believe we're offline.
        //
        // `BackendService.restoreSession()` awaits `supabase.auth.session`, which refreshes an
        // expired token over the network, and `loadSignedInState()` then makes several more calls
        // in sequence; with no connectivity every one has to time out before the splash clears,
        // measured at ~45s on a cold launch.
        //
        // This used to be gated on `!NetworkMonitor.shared.isConnected`, which never fired at
        // launch: `isConnected` defaults to `true` and `NWPathMonitor` delivers its first real
        // reading asynchronously, so at the instant this runs — the first thing the app does — the
        // monitor still says connected even in airplane mode. The gate was the whole fix, and it
        // was racing something it could never win.
        //
        // Ungated, it doesn't need to win: `currentSession` reads the locally-stored session with
        // no network at all, so an account that has run before shows its cached state immediately
        // and the refresh below overwrites it whenever the network answers. The stale-then-fresh
        // flip that gate existed to avoid is between two states of the same account, usually
        // identical, and lasts as long as one round trip. That is a far smaller cost than a splash
        // screen that never clears — and it covers what the monitor cannot see at all: a captive
        // portal, or a connection too slow to finish.
        if let userID = BackendService.currentUserID,
           let cached = OfflineSessionCache.restore(for: userID) {
            applyCachedSession(cached)
            hasCouple = true
            isLoadingSession = false
        }

        guard await BackendService.restoreSession() != nil else { return }
        await loadSignedInState()
    }

    /// Replays the last-known trips/flights/memories from disk. Only ever called once the live
    /// fetches have already failed, so it can't overwrite fresher server data.
    ///
    /// Anything still pending sync wins over its cached copy: `restorePendingTripsFromDisk()`/
    /// `restorePendingMemoriesFromDisk()` run earlier in `loadSignedInState`, and those are the
    /// user's newest work — a stale server snapshot must not clobber something they added offline
    /// and haven't uploaded yet.
    private func applyCachedTravelData() {
        guard let cached = OfflineDataCache.restore(for: BackendService.currentUserID) else { return }
        let pendingTrips = trips.filter { pendingTripIDs.contains($0.id) }
        let pendingMemories = memories.filter { pendingMemoryIDs.contains($0.id) }
        trips = cached.trips.filter { !pendingTripIDs.contains($0.id) } + pendingTrips
        memories = cached.memories.filter { !pendingMemoryIDs.contains($0.id) } + pendingMemories
        flights = cached.flights
        // Only fill a city that isn't already known — a live value from the backend is better than
        // a cached one, and this also runs on paths where some state is already real.
        if couple.partnerA.homeCity == nil { couple.partnerA.homeCity = cached.myCity }
        if couple.partnerB.homeCity == nil { couple.partnerB.homeCity = cached.partnerCity }
        if couple.partnerA.avatarURL == nil { couple.partnerA.avatarURL = cached.myAvatarURL }
        if couple.partnerB.avatarURL == nil { couple.partnerB.avatarURL = cached.partnerAvatarURL }
        // The couple's own fields, and only while `couple` is still the placeholder — once
        // `performAdopt` has run, `couple.id` matches the cached one and the live values stand.
        // `placeholderCouple` dates the relationship to `.now`, so without this the Stats screen
        // opened offline saying a couple of nine years had been together for zero days.
        if couple.id != cached.coupleID {
            if let startedDatingOn = cached.startedDatingOn { couple.startedDatingOn = startedDatingOn }
            if couple.connectedAt == nil { couple.connectedAt = cached.connectedAt }
            if couple.maxDistanceKm == nil { couple.maxDistanceKm = cached.maxDistanceKm }
        }
        applyCachedGameState()
    }

    /// The streak and today's question, restored the same way and for the same reason as the rest:
    /// they're only ever set by a backend call, so offline they sat at zero and nil.
    private func applyCachedGameState() {
        guard let cached = OfflineGameStateCache.restore(for: BackendService.currentUserID) else { return }
        if dailyStreak == nil { dailyStreak = cached.dailyStreak }
        if longestDailyStreak == nil { longestDailyStreak = cached.longestDailyStreak }
        if dailyStreakResetsAt == nil { dailyStreakResetsAt = cached.dailyStreakResetsAt }
        if todaysDailyQuestionText == nil {
            todaysDailyQuestionText = cached.questionText
            todaysDailySessionID = cached.questionSessionID
            todaysMyAnswered = cached.myAnswered
            todaysPartnerAnswered = cached.partnerAnswered
        }
        if deckProgress == nil { deckProgress = cached.deckProgress }
    }

    /// Guards against a second pass piling on top of one already in flight — `performAdopt` runs
    /// on every foreground refresh, not just at launch.
    private var isPrefetchingMemoryPhotos = false

    /// Pulls memory photos onto disk ahead of time so they're actually there when there's no
    /// connection. Caching on display alone isn't enough for the case this exists for: a photo is
    /// only cached if you happened to scroll past it *before* losing signal, so browsing memories
    /// on a plane would still be mostly empty placeholders.
    ///
    /// Newest-first because that's what people scroll to, bounded by `MemoryPhotoDiskCache`'s own
    /// size limit afterwards, and skipped on a metered connection — silently pulling hundreds of
    /// megabytes over cellular to pre-empt a trip someone may not be taking is not a reasonable
    /// trade. Runs detached at low priority; every failure is skipped rather than retried, since
    /// the display path re-downloads on demand anyway.
    private func prefetchMemoryPhotos() {
        guard !isPrefetchingMemoryPhotos else { return }
        guard NetworkMonitor.shared.isConnected, !NetworkMonitor.shared.isExpensive else { return }

        let photos = memories
            .sorted { $0.date > $1.date }
            .flatMap(\.photos)
            .filter { $0.path != "pending" && !MemoryPhotoDiskCache.has(path: $0.path) }
        guard !photos.isEmpty else { return }

        isPrefetchingMemoryPhotos = true
        Task.detached(priority: .background) {
            for photo in photos {
                guard let (data, _) = try? await URLSession.shared.data(from: photo.url) else { continue }
                MemoryPhotoDiskCache.write(data, path: photo.path)
            }
            MemoryPhotoDiskCache.enforceSizeLimit()
            await MainActor.run { self.isPrefetchingMemoryPhotos = false }
        }
    }

    /// Called any time we know a Supabase session exists — at launch (`restoreSession`), right
    /// after a manual sign-in (`SignInView`), or after `removePartner()` dissolves a couple.
    /// Being authenticated at all means onboarding is already done, regardless of whether a
    /// `couples` row exists yet — so this always ends with `hasCouple = true`, rather than
    /// leaving a solo (unpaired) user to fall back into onboarding just because
    /// `fetchCoupleState` found nothing.
    func loadSignedInState() async {
        // Backstop for a soft-deleted account whose session (or whose Apple/Google identity)
        // can still resolve to a signed-in state — see `BackendService.currentAccountIsDeleted()`.
        // Must run before anything else touches profile/couple state, so a scrubbed, deleted
        // account is never actually adopted and shown.
        if await BackendService.currentAccountIsDeleted() {
            try? await BackendService.signOut()
            accountDeletedMessage = "This account has been deleted and can't be signed back into. Create a new account to keep using Twofold."
            isLoadingSession = false
            return
        }
        await retryPendingPushTokenRegistrationIfNeeded()
        try? await BackendService.updateDeviceContext()
        await identifyWithRevenueCat()
        identifyWithPostHog()
        restorePendingMemoriesFromDisk()
        restorePendingTripsFromDisk()
        let outcome = await CoupleStateOutcome.fetch()
        if case let .paired(state) = outcome {
            await adopt(state)
        } else if case .noCouple = outcome, let profile = try? await BackendService.fetchOwnProfile() {
            // Only when the backend actually said so. A failed fetch used to land here too, so a
            // launch on a flaky connection could show a paired couple their solo, unpaired app.
            await adoptSoloProfile(profile)
        } else if let cached = OfflineSessionCache.restore(for: BackendService.currentUserID) {
            // Both reads failed — almost always no network (they're `try?`, so a real outage looks
            // identical to "no rows"). Without this, `isSubscriptionActive` keeps its `false`
            // default while `hasCouple` is set to true just below, and `RootView` drops a paying
            // subscriber onto the non-dismissable paywall.
            applyCachedSession(cached)
        }
        hasCouple = true
        // Resolved here, not only from RootView's launch task.
        //
        // That task runs once, at launch. Someone who opens the app signed out gets an early
        // return from it (`guard hasCouple`) that leaves `hasResolvedOutgoingConnectionRequest`
        // false, and then signs in — at which point `hasCouple` flips true, RootView re-renders,
        // and its paywall-exemption gate holds them on the loading screen forever because nothing
        // remains to resolve the flag. A real sign-in that ends in an infinite beating heart.
        //
        // Tying it to `hasCouple` instead means every path that admits someone to the app resolves
        // it: launch, manual sign-in, and password recovery all end up here. The call is cheap for
        // a paired couple — `refreshPendingOutgoingConnectionRequest` returns without a round trip
        // when `partnerConnected`.
        await refreshPendingOutgoingConnectionRequest()
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        checkReviewMilestones()
    }

    /// Unpacks a cached snapshot into the live state — the couple's names, what they've paid for,
    /// and their travel data. Called from both launch paths so there's one definition of what
    /// "the app, from cache" means rather than two that can drift.
    ///
    /// Deliberately doesn't touch `hasCouple` or `isLoadingSession`: what a cache means for routing
    /// differs between a pre-network launch and a post-failure fallback, so those stay with the
    /// caller that knows which it is.
    private func applyCachedSession(_ cached: OfflineSessionCache.Snapshot) {
        isSubscriptionActive = cached.active
        subscriptionTier = cached.tier
        partnerConnected = cached.partnerConnected
        if let myName = cached.myName, !myName.isEmpty { couple.partnerA.name = myName }
        if let partnerName = cached.partnerName, !partnerName.isEmpty { couple.partnerB.name = partnerName }
        partnerConnectedCelebrationShown = cached.celebrationShown
        setupChecklistDismissed = cached.checklistDismissed
        restorePendingMemoriesFromDisk()
        restorePendingTripsFromDisk()
        applyCachedTravelData()
    }

    /// Restores memories that were added before pairing (or otherwise never synced) from local
    /// disk — see `PendingMemoryStore`. Runs before `adopt(_:)`/`adoptSoloProfile(_:)` so
    /// whichever one runs next already sees them: `adopt(_:)` will attempt to sync them
    /// immediately (they're now in `pendingMemoryIDs`), and `adoptSoloProfile(_:)` preserves
    /// pending memories through its reset rather than discarding them. Skips anything already
    /// present (e.g. a second call this session) to avoid duplicate entries.
    private func restorePendingMemoriesFromDisk() {
        for (memory, photosData) in PendingMemoryStore.loadAll() {
            guard !memories.contains(where: { $0.id == memory.id }) else { continue }
            memories.append(memory)
            pendingMemoryIDs.insert(memory.id)
            if !photosData.isEmpty { pendingMemoryPhotoData[memory.id] = photosData }
        }
    }

    /// Restores trips that were added before pairing (or otherwise never synced) from local
    /// disk — see `PendingTripStore`. Same placement/reasoning as
    /// `restorePendingMemoriesFromDisk()` just above.
    private func restorePendingTripsFromDisk() {
        for trip in PendingTripStore.loadAll() {
            guard !trips.contains(where: { $0.id == trip.id }) else { continue }
            trips.append(trip)
            pendingTripIDs.insert(trip.id)
        }
    }

    /// Resets to the solo (unpaired) state and repopulates from the caller's own profile —
    /// shared by `loadSignedInState()` (launch/sign-in) and `refreshCoupleStateIfNeeded()`
    /// (an already-connected device discovering the couple was dissolved elsewhere). Reset
    /// first: at launch these are already at their zero-value defaults so it's a no-op, but
    /// reused mid-session this clears the *old* partner's data (partnerConnected,
    /// backendCoupleID, trips/memories/flights, drawing pad URLs) that would otherwise survive
    /// and make a just-dissolved couple still look "connected" in the UI. Trips/memories still in
    /// `pendingTripIDs`/`pendingMemoryIDs` are the exception — they were never tied to any
    /// couple in the first place (added before ever pairing, still only durable via
    /// `PendingTripStore`/`PendingMemoryStore`), so they survive this reset rather than being
    /// discarded along with the dissolved couple's data.
    private func adoptSoloProfile(_ profile: BackendService.OwnProfileState) async {
        await stopFlightsRealtimeSubscription()
        if partnerConnected {
            let name = couple.partnerB.name.isEmpty ? "your partner" : couple.partnerB.name
            partnerDisconnectedMessage = "We're sorry — your connection with \(name) has ended. Nothing has been deleted; your shared trips, memories, and flights are still there, safe and yours to look back on or export anytime from Settings."
        }
        partnerConnected = false
        backendCoupleID = nil
        trips = trips.filter { pendingTripIDs.contains($0.id) }
        memories = memories.filter { pendingMemoryIDs.contains($0.id) }
        flights = []
        // Unlike every other path that clears `flights`, this one can't just call
        // `refreshFlights()` afterward to reconcile Live Activities — it guards on
        // `backendCoupleID`, which is already nil above. Ending against an empty list directly
        // instead, so a flight-tracking Live Activity doesn't keep showing (now stale, since the
        // couple that authorized it no longer exists) until the app happens to background/
        // foreground or relaunch.
        await LiveActivityManager.shared.syncActivities(
            for: [],
            participants: { _ in JourneyParticipants(travelerName: "", partnerName: "", viewerIsTraveler: false) },
            isReunion: { _ in false }
        )
        myDrawingURL = nil
        partnerDrawingURL = nil
        couple = Self.placeholderCouple

        couple.partnerA = profile.person
        if let partnerName = profile.partnerName, !partnerName.isEmpty {
            couple.partnerB.name = partnerName
        }
        if let partnerHomeCity = profile.partnerHomeCity {
            couple.partnerB.homeCity = partnerHomeCity
        }
        if let partnerAvatarURL = profile.partnerAvatarURL {
            couple.partnerB.avatarURL = partnerAvatarURL
        }
        if let anniversaryDate = profile.anniversaryDate {
            couple.startedDatingOn = anniversaryDate
        }
        isSubscriptionActive = profile.subscriptionActive
        subscriptionTier = profile.subscriptionTier
        // Same reasoning as `performAdopt` — see OfflineSessionCache. Solo (unpaired) here, so
        // partnerConnected is false; restoring that keeps the setup card honest either way.
        OfflineSessionCache.record(
            active: profile.subscriptionActive,
            tier: profile.subscriptionTier,
            userID: BackendService.currentUserID,
            partnerConnected: false,
            myName: profile.person.name,
            partnerName: profile.partnerName,
            celebrationShown: profile.partnerConnectedCelebrationShown,
            checklistDismissed: profile.setupChecklistDismissed
        )
        partnerConnectedCelebrationShown = profile.partnerConnectedCelebrationShown
        setupChecklistDismissed = profile.setupChecklistDismissed
        partnerSubscriptionLapsedPartnerName = profile.partnerSubscriptionLapseShown ? nil : profile.partnerSubscriptionLapsePartnerName
    }

    /// A device's own successful purchase/restore, applied instantly and locally (no network
    /// round-trip) — `PaywallView` calls this right after a purchase/restore succeeds, before
    /// its own `onSubscribed()` callback fires, so `RootView`'s gate never flashes a second
    /// paywall for someone who just subscribed (the Supabase write happens alongside this, but
    /// this local flag is what `RootView` actually reads). Also updates `subscriptionTier` and
    /// pushes a fresh widget snapshot immediately — previously only `isSubscriptionActive` was
    /// set here, so tier-gated UI (`isDeckLocked`/`isPremiumLocked`, Home's plan-dependent
    /// copy) and widgets stayed on the pre-purchase tier until the next foreground/relaunch's
    /// `performAdopt` round trip.
    func markSubscriptionActive(tier: String) {
        isSubscriptionActive = true
        subscriptionTier = tier
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }

    /// Flips instantly (so the caller's UI never shows the celebration twice in one session)
    /// and persists server-side in the background — see `BackendService.markPartnerConnectedCelebrationShown`.
    func markPartnerConnectedCelebrationShown() {
        guard !partnerConnectedCelebrationShown else { return }
        partnerConnectedCelebrationShown = true
        Task { await BackendService.markPartnerConnectedCelebrationShown() }
    }

    /// Same pattern as `markPartnerConnectedCelebrationShown()` — instant local flip (so
    /// `SubscriptionLapsedFromDisconnectView` never shows twice in one session), persisted
    /// server-side in the background. Re-armable: `leave_couple` can set the underlying flag back
    /// to `false` again later, for a different relationship's same non-payer outcome.
    func markPartnerSubscriptionLapseAcknowledged() {
        guard partnerSubscriptionLapsedPartnerName != nil else { return }
        partnerSubscriptionLapsedPartnerName = nil
        Task { await BackendService.markPartnerSubscriptionLapseShown() }
    }

    /// Same pattern as `markPartnerConnectedCelebrationShown()` — instant local flip, persisted
    /// server-side in the background.
    func dismissSetupChecklist() {
        guard !setupChecklistDismissed else { return }
        setupChecklistDismissed = true
        Task { await BackendService.markSetupChecklistDismissed() }
    }

    /// Tells RevenueCat who this device's user actually is, so its entitlement/purchase history
    /// is attributed to the same identity across every device that signs into this account —
    /// without this, RevenueCat would only ever see its own locally-generated anonymous ID,
    /// which a reinstall or a second device would never line up with. `Purchases.configure`
    /// (see `RevenueCatConfig`) runs before any Supabase session is known, so this is the
    /// earliest point that identity is actually available — called from `loadSignedInState()`
    /// itself rather than deeper in `adopt`/`adoptSoloProfile` since both of those paths need it
    /// equally and neither should have to remember to call it separately.
    private func identifyWithRevenueCat() async {
        guard let userID = BackendService.currentUserID else { return }
        if (try? await Purchases.shared.logIn(userID.uuidString)) == nil {
            // One retry — a `logIn` failure here (typically a network blip right at launch/sign-in)
            // is exactly what leaves RevenueCat on its anonymous ID for the rest of the session,
            // which `RootView.deviceHoldsEntitlement`'s `isAnonymous` check exists to stay safe against
            // regardless, but a second attempt costs nothing and fixes the common transient case
            // outright rather than just avoiding its worst consequence.
            _ = try? await Purchases.shared.logIn(userID.uuidString)
        }

        // Puts the account's email on the RevenueCat customer, purely so a person is findable in
        // that dashboard. `app_user_id` is the Supabase UUID and nothing else about the customer
        // identifies them, so answering "why is this subscriber on Premium?" meant copying a UUID
        // out of RevenueCat and querying Postgres with it, every time.
        //
        // `$email` is a reserved attribute — RevenueCat surfaces it on the customer profile rather
        // than filing it as an arbitrary key. Sent after `logIn` on purpose: attributes attach to
        // whichever customer is current, so setting it first would put the email on the anonymous
        // id that `logIn` is about to leave behind.
        //
        // Fire-and-forget by design: the SDK queues attributes locally and flushes them with the
        // next backend call, so there is nothing to await and a failure here must never affect
        // whether someone can use the app.
        if let email = BackendService.currentUserEmail {
            Purchases.shared.attribution.setEmail(email)
        }
    }

    /// Same idea as `identifyWithRevenueCat()`, for PostHog — ties analytics events to the same
    /// stable Supabase user id instead of PostHog's own throwaway anonymous id, so a signed-in
    /// user's activity lines up across devices/reinstalls. Synchronous (unlike the RevenueCat
    /// call): `PostHogSDK.identify(_:)` just queues locally, no network round-trip to await.
    private func identifyWithPostHog() {
        guard let userID = BackendService.currentUserID else { return }
        PostHogSDK.shared.identify(userID.uuidString)
    }

    /// Signs out and resets all local state back to the pre-auth placeholder — `RootView`
    /// picks this up via `hasCouple` and routes back to `WelcomeView`.
    func signOut() async {
        await stopFlightsRealtimeSubscription()
        // Must happen *before* `BackendService.signOut()` — unregistering relies on the
        // `device_push_tokens` "delete own" RLS policy, which needs `auth.uid()` to still resolve
        // to this account. Best-effort: a failure here just means this device keeps getting
        // pushed to until a different account signs in and reassigns the token, same as before
        // this existed — not worth blocking sign-out over.
        if let lastRegisteredPushTokenHex {
            try? await BackendService.unregisterDeviceToken(lastRegisteredPushTokenHex)
        }
        try? await BackendService.signOut()
        await clearLocalSessionState()
    }

    /// Permanently deletes this account (see `BackendService.deleteAccount()`'s doc comment for
    /// exactly what that does server-side) and clears local state the same way `signOut()`
    /// does — the account is gone either way, so the device needs to end up in the same signed-
    /// out state. Rethrows so the caller (the confirmation screen) can show a real error instead
    /// of silently doing nothing if the request fails.
    ///
    /// - Parameter deleteSharedData: also permanently delete the shared archives (trips,
    ///   memories, photos, flights) for both partners — see `BackendService.deleteAccount()`.
    func deleteAccount(deleteSharedData: Bool = false) async throws {
        await stopFlightsRealtimeSubscription()
        try await BackendService.deleteAccount(deleteSharedData: deleteSharedData)
        await clearLocalSessionState()
    }

    /// Shared by `signOut()` and `deleteAccount()` — both end with the device in the same
    /// signed-out state, whether the account still exists (just logged out of) or not (deleted).
    private func clearLocalSessionState() async {
        _ = try? await Purchases.shared.logOut()
        PostHogSDK.shared.reset()
        // Without this, Home Screen widgets and Live Activities kept showing the signed-out
        // account's (and their partner's) name, photos, anniversary date, and upcoming trip/
        // flight until a different account signed in and overwrote them — none of this was
        // previously cleared by sign-out at all.
        await LiveActivityManager.shared.endAll()
        // Same reasoning as the widget snapshot below — the next account to sign in on this device
        // must not inherit this one's entitlement. (`restore(for:)` is account-scoped as a second
        // guard, but clearing on the way out is the honest place to do it.)
        OfflineSessionCache.clear()
        OfflineDataCache.clear()
        OfflineGameStateCache.clear()
        LocalGameSessionStore.clear()
        PendingGameResponseStore.clear()
        // Every generated game's saved progress at once. One call rather than one per game, so a
        // game added later cannot leave its half-finished puzzle behind for the next account.
        PuzzleProgressCache.clearAll()
        // The catalogue itself, not just this account's view of it — the next person signing in
        // falls back to the bundled seed until their own refresh runs, rather than inheriting a
        // copy fetched under someone else's subscription tier.
        GameContentStore.clear()
        MemoryPhotoDiskCache.clear()
        RemoteImageDiskCache.clear()
        WidgetSnapshot.clear()
        WidgetImageCache.clearAll()
        WidgetCenter.shared.reloadAllTimelines()
        // Any push that already landed for the signed-out account (a trip/game update, a flight
        // alert) otherwise sat in Notification Center indefinitely, and tapping it after sign-out
        // routed into content that either no longer resolves or belongs to whoever signs in next.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        lastRegisteredPushTokenHex = nil
        hasCouple = false
        partnerConnected = false
        inviteCode = nil
        backendCoupleID = nil
        isSubscriptionActive = false
        pendingTripIDs = []
        pendingMemoryIDs = []
        pendingMemoryPhotoData = [:]
        pendingFlightCandidates = [:]
        trips = []
        memories = []
        flights = []
        couple = Self.placeholderCouple
        // Otherwise `loadGameDecksIfNeeded()`'s nil-guard treats this account's Games hub as
        // already loaded and shows the previous account's deck progress until something else
        // happens to call `refreshGameDecks()` unconditionally.
        gameDecks = nil
        deckProgress = nil
    }

    private static var placeholderCouple: Couple {
        Couple(
            partnerA: Person(name: "You", accentColor: Person.palette[1]),
            partnerB: Person(name: "Partner", accentColor: Person.palette[0]),
            startedDatingOn: .now
        )
    }

    /// Persists profile edits from `SettingsView`. Each field only round-trips to the backend
    /// if it actually changed, since `updateFirstName`/`updateHomeCity` are separate writes.
    func updateProfile(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != couple.partnerA.name {
            try? await BackendService.updateFirstName(trimmedName)
            couple.partnerA.name = trimmedName
        }
    }

    func updateAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadAvatar(imageData: imageData)
        AvatarView.preloadCache(imageData: imageData, url: url)
        couple.partnerA.avatarURL = url
    }

    /// Always editable, paired or not — this is *your own, personal* name for your partner
    /// (a nickname, a pet name, whatever you call them), never their real account data. Your
    /// partner has their own independent nickname for you, if they've set one; neither side
    /// overwrites the other's. See `BackendService.updatePartnerNickname`.
    func updatePartnerName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != couple.partnerB.name else { return }
        try? await BackendService.updatePartnerNickname(trimmed)
        couple.partnerB.name = trimmed
    }

    /// Unlike the name (always personal), the city is shared/real once paired — only
    /// meaningful to set here before that, as a personalization guess. `SettingsView` disables
    /// this field once `partnerConnected` is true.
    func updatePartnerHomeCity(_ city: Place) async {
        guard city.id != couple.partnerB.homeCity?.id else { return }
        try? await BackendService.updatePartnerHomeCityGuess(city)
        couple.partnerB.homeCity = city
    }

    /// Always personal, paired or not — it's always *your own* custom photo of your partner,
    /// independent of whatever avatar they picked for themselves (see
    /// `BackendService.uploadPartnerAvatar`).
    func updatePartnerAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadPartnerAvatar(imageData: imageData)
        AvatarView.preloadCache(imageData: imageData, url: url)
        couple.partnerB.avatarURL = url
    }

    /// Once paired, `couples.started_dating_on` is the value re-fetches actually read back
    /// (`profiles.anniversary_date` only matters pre-pairing), so this must target whichever one
    /// is actually authoritative right now or the edit silently reverts on the next refresh.
    func updateAnniversaryDate(_ date: Date) async {
        guard date != couple.startedDatingOn else { return }
        if let coupleID = backendCoupleID {
            try? await BackendService.updateCoupleAnniversaryDate(coupleID: coupleID, date: date)
        } else {
            try? await BackendService.updateAnniversaryDate(date)
        }
        couple.startedDatingOn = date
    }

    /// Incoming connection requests (double verification — see the migration's own header
    /// comment) — safe to call any time, including while already connected (just returns
    /// empty), so call sites don't need to guard on `partnerConnected` themselves.
    func refreshPendingConnectionRequests() async {
        pendingConnectionRequests = (try? await BackendService.fetchPendingConnectionRequests()) ?? []
    }

    /// My own outgoing request (see `pendingOutgoingConnectionRequest`'s doc comment). Guarded on
    /// `!partnerConnected` for two reasons: efficiency (this now runs on every foreground — see
    /// `RootView.refreshPendingOutgoingConnectionRequestIfNeeded` — so a genuinely paired couple
    /// shouldn't pay for a network round trip that can only ever come back empty for them), and
    /// correctness. The "only" in the old version of this comment was wrong: nothing stops
    /// redeeming a second code while a first request is still unresolved, so
    /// `fetchMyOutgoingConnectionRequest()`'s "most recent pending" query can keep surfacing an
    /// abandoned request from *before* pairing even after a different one got accepted — without
    /// this guard, Home's pending-invite card would wrongly show for someone who's actually
    /// already connected.
    func refreshPendingOutgoingConnectionRequest() async {
        guard !partnerConnected else {
            pendingOutgoingConnectionRequest = nil
            hasResolvedOutgoingConnectionRequest = true
            return
        }
        // Retried once, because a failure here is not the same as an empty answer and the two are
        // indistinguishable downstream.
        //
        // `pendingOutgoingConnectionRequest == nil` means both "there is no request" and "we could
        // not find out". RootView reads nil as no-exemption and shows the paywall; Home reads it as
        // not-invited and shows the generic invite card. So one failed call — a token still
        // settling moments after sign-in is enough — flashes a paywall at someone waiting on their
        // partner, then corrects itself when the next refresh succeeds. That is what this fixes.
        //
        // Still resolves after the second attempt rather than looping: a network that is genuinely
        // down must not hold anyone on a loading screen forever, and after two tries the honest
        // answer is that we do not know.
        var fetched: BackendService.OutgoingConnectionRequest?
        var succeeded = false
        for attempt in 0..<2 {
            do {
                fetched = try await BackendService.fetchMyOutgoingConnectionRequest()
                succeeded = true
                break
            } catch {
                // A short pause before the retry. The failure this exists for is a session that is
                // a moment from being usable, not one that is broken.
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }

        // Only overwrite what we know with what we found if we actually found out. A failed pair of
        // attempts leaves any previously-known request standing rather than erasing it.
        if succeeded { pendingOutgoingConnectionRequest = fetched }
        hasResolvedOutgoingConnectionRequest = true
    }

    /// Nudges the inviter on `pendingOutgoingConnectionRequest`. Returns an error message on
    /// failure (including the RPC's own cooldown-rejection text), nil on success — same shape as
    /// `removePartner()`.
    @discardableResult
    func sendConnectionRequestReminder() async -> String? {
        guard let request = pendingOutgoingConnectionRequest else { return "No pending request to remind." }
        do {
            try await BackendService.sendConnectionRequestReminder(requestID: request.id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Accepts or declines an incoming request. On accept, re-checks couple state immediately
    /// rather than waiting for the next foreground/background refresh — the whole point of
    /// accepting right now is to connect right now. Returns an error message on failure, nil on
    /// success (same shape as `removePartner()`).
    @discardableResult
    func respondToConnectionRequest(
        _ request: BackendService.PendingConnectionRequest,
        accept: Bool,
        restoreArchive: Bool = false
    ) async -> String? {
        do {
            let coupleID = try await BackendService.respondToConnectionRequest(
                id: request.id, accept: accept, restoreArchive: restoreArchive
            )
            pendingConnectionRequests.removeAll { $0.id == request.id }
            if coupleID != nil {
                await refreshCoupleStateIfNeeded()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Ends the current partnership. The couple row is dissolved, not deleted — every trip,
    /// memory, flight, and game session shared with them stays intact and stays readable later
    /// (only visible via Settings' "Archived data" screen, and only ever deleted for good if the
    /// user explicitly asks). Reloads signed-in state afterward, which naturally falls back to
    /// the same solo/not-yet-paired shape a brand-new user starts in — reuses
    /// `loadSignedInState()`'s existing "no active couple" branch rather than duplicating that
    /// reset logic here. Returns nil on success, or a message describing what went wrong — the
    /// underlying RPC's own rejection (e.g. "This couple has already been dissolved") is
    /// relayed rather than swallowed, since a generic error here gives no way to tell a real
    /// failure apart from a harmless double-tap/retry.
    func removePartner() async -> String? {
        guard let backendCoupleID else { return "No partner to remove." }
        do {
            try await BackendService.leaveCouple(coupleID: backendCoupleID)
        } catch {
            return error.localizedDescription
        }
        Analytics.capture(Analytics.Event.partnerRemove)
        // The old code is now permanently invalid server-side (`redeem_invite_code` rejects a
        // non-"pending" code) — without clearing it, `PartnerConnectCard`'s `if inviteCode ==
        // nil` guard would reshare this same dead code to whoever the user invites next, and
        // their redemption attempt would fail with no obvious reason why.
        inviteCode = nil
        await loadSignedInState()
        // HomeView's setup checklist card (the "invite your partner" hint) remembers a past
        // dismissal forever, server-side — without resetting it, someone who'd already
        // dismissed it once (e.g. during their original onboarding) would see no hint at all
        // here, even though they're now genuinely back in the same unpaired state a brand-new
        // user starts in and need that same nudge again.
        setupChecklistDismissed = false
        Task { await BackendService.resetSetupChecklistDismissed() }
        return nil
    }

    /// Re-checks backend couple state without touching `isLoadingSession` — picks up a
    /// partner's invite redemption that happened while this device was backgrounded, the
    /// same idea as `GlobeHomeView`'s existing pending-share foreground refresh.
    /// Called on Home appearing/foregrounding — the name says "if needed" but it always
    /// re-checks now, in both directions: picks up a partner who just joined, *and* notices if
    /// an already-connected couple was dissolved elsewhere (another device, or directly) since
    /// this device last checked. Skipping the re-check whenever `partnerConnected` was already
    /// true used to mean a device could keep showing "connected" indefinitely after the couple
    /// was actually dissolved, until a full sign-out/sign-in or cold relaunch.
    func refreshCoupleStateIfNeeded() async {
        guard hasCouple else { return }
        switch await CoupleStateOutcome.fetch() {
        case let .paired(state):
            await adopt(state)
        case .noCouple:
            // The backend answered, and there is no active couple. This is the only outcome that
            // may tear down a pairing — see `CoupleStateOutcome` for the Wi-Fi blip that used to
            // reach here and announce that the partner had disconnected.
            if partnerConnected, let profile = try? await BackendService.fetchOwnProfile() {
                await adoptSoloProfile(profile)
            }
        case .unknown:
            break
        }
    }

    /// Drawing pad paths are fully deterministic (`{coupleID}/{personID}/pad.png`), so unlike
    /// trips/memories there's nothing to "fetch" beyond just pointing at a URL — this just primes
    /// both URLs so the pad previews have something to render on first appearance.
    ///
    /// `drawing-pads` is a private bucket now (see `BackendService.drawingPadSignedURL`'s doc
    /// comment), so this needs a real signed-URL round trip rather than just building a public
    /// URL string — and since each signed URL embeds its own unique token, it's never the same
    /// string twice, which is what used to require the separate manual cache-busting step here
    /// (re-fired from `DrawingPadCard.onAppear` on top of whatever `saveMyDrawing` just set).
    func loadDrawingPads() async {
        guard let backendCoupleID else { return }
        myDrawingURL = try? await BackendService.drawingPadSignedURL(coupleID: backendCoupleID, personID: currentUser.id)
        partnerDrawingURL = try? await BackendService.drawingPadSignedURL(coupleID: backendCoupleID, personID: partner.id)
    }

    /// Fires once — the first time a couple both (a) has a connected partner and (b) has already
    /// done something with the app (a trip, memory, or tracked flight). Deliberately not keyed to
    /// any one of those in isolation — the couple isn't "connected" yet during onboarding
    /// (`hasCouple` only flips true at the very end), so this can never fire mid-onboarding, and
    /// asking right after a still-solo first action reads as premature. "First game results" isn't
    /// state AppModel tracks directly, so that one's raised via `noteReviewMilestone(_:)` from
    /// `GameResultsView` instead.
    func checkReviewMilestones() {
        guard hasCouple, partnerConnected, pendingReviewMilestone == nil else { return }
        guard !trips.isEmpty || !memories.isEmpty || !flights.isEmpty else { return }
        if ReviewPromptService.markShownIfEligible(.partnerConnected) {
            pendingReviewMilestone = .partnerConnected
        }
    }

    /// For the one milestone AppModel can't derive from its own state.
    func noteReviewMilestone(_ milestone: ReviewMilestone) {
        guard pendingReviewMilestone == nil, ReviewPromptService.markShownIfEligible(milestone) else { return }
        pendingReviewMilestone = milestone
    }

    /// Call after a solo (unpaired) user finishes adding a trip/memory or completes a game —
    /// surfaces `PartnerInviteNudgeView` at most once a day. No-ops once paired (nothing left to
    /// invite anyone to) or while a request is already pending (they've already invited someone —
    /// Home's own pending-invite card, not this nudge, is the right prompt for that state).
    func noteSoloActionCompleted() {
        guard !partnerConnected, pendingOutgoingConnectionRequest == nil, PartnerInviteNudgeService.isEligibleToday() else { return }
        pendingPartnerInviteNudge = true
        PartnerInviteNudgeService.markShown()
    }

    // MARK: - Games: Daily Activity + topic browsing

    /// Fetches (or creates, server-side) today's Daily Activity session and refreshes the
    /// streak — called when the Games hub appears, not at launch, since it's Games-specific.
    func startOrResumeDailyQuestion() async {
        dailyQuestionError = nil
        isLoadingDailyQuestion = true
        defer { isLoadingDailyQuestion = false }
        // Same reason as `refreshGameDecks`: offline these calls only fail, and only after a full
        // timeout each, so the card spun for a minute before showing the question already cached
        // from earlier today.
        guard NetworkMonitor.shared.isConnected else {
            applyCachedDailyQuestion()
            return
        }
        do {
            let sessionID = try await BackendService.getDailyQuestionSession()
            todaysDailySessionID = sessionID
            if let detail = try? await BackendService.fetchGameSession(id: sessionID),
               let round = detail.rounds.first, case let .deepConversation(topic)? = detail.content[round.contentID] {
                todaysDailyQuestionText = topic.topic
            }
        } catch {
            applyCachedDailyQuestion()
        }
        if let status = try? await BackendService.fetchDailyQuestionStatus() {
            todaysMyAnswered = status.mine
            todaysPartnerAnswered = status.partner
        }
        await refreshDailyStreak()
        recordGameStateForOffline()
    }

    /// Only asked when there is plainly something to ask about: a streak reading zero. The
    /// repairable window needs the couple's own local dates to evaluate, so it is a round trip, and
    /// a couple mid-streak has no use for the answer.
    func refreshStreakRepairState() async {
        guard NetworkMonitor.shared.isConnected, partnerConnected, dailyStreak == 0 else {
            streakRepair = nil
            return
        }
        streakRepair = try? await BackendService.streakRepairState()
    }

    func refreshDailyStreak() async {
        // `refreshAll()` runs this alongside five other fetches on every foreground and every
        // pull-to-refresh; offline it can only wait out a timeout, holding that whole group open.
        guard NetworkMonitor.shared.isConnected else { return }
        if let streak = try? await BackendService.fetchDailyStreak() {
            dailyStreak = streak.current
            longestDailyStreak = streak.longest
            dailyStreakResetsAt = streak.resetsAt
            recordGameStateForOffline()
        }
        await refreshStreakRepairState()
    }

    /// Today's question as of the last time it was fetched. The backend assigns one per day, so a
    /// question cached earlier today is the same question, not a guess at it — which is why this
    /// only restores one recorded today, and reports a real error otherwise.
    private func applyCachedDailyQuestion() {
        if let cached = OfflineGameStateCache.restore(for: BackendService.currentUserID),
           let text = cached.questionText {
            todaysDailyQuestionText = text
            todaysDailySessionID = cached.questionSessionID
            todaysMyAnswered = cached.myAnswered
            todaysPartnerAnswered = cached.partnerAnswered
            if dailyStreak == nil { dailyStreak = cached.dailyStreak }
            if longestDailyStreak == nil { longestDailyStreak = cached.longestDailyStreak }
            if dailyStreakResetsAt == nil { dailyStreakResetsAt = cached.dailyStreakResetsAt }
        } else {
            dailyQuestionError = "Today's question needs a connection. Decks below are ready to play."
        }
    }

    /// Keeps the streak and today's question on disk so the Games hub has something to show with
    /// no network — otherwise a 40-day streak read as zero, which is the one number in the app
    /// nobody wants to see wrong.
    func recordGameStateForOffline() {
        OfflineGameStateCache.record(
            dailyStreak: dailyStreak,
            longestDailyStreak: longestDailyStreak,
            dailyStreakResetsAt: dailyStreakResetsAt,
            questionText: todaysDailyQuestionText,
            questionSessionID: todaysDailySessionID,
            myAnswered: todaysMyAnswered,
            partnerAnswered: todaysPartnerAnswered,
            deckProgress: deckProgress,
            userID: BackendService.currentUserID
        )
    }

    #if DEBUG
    /// How many times `refreshAll()` has been entered. Exists so a UI test can prove the
    /// pull-to-refresh gesture is actually wired up, which cannot be done by looking for the
    /// spinner: XCUITest quiesces the app before every accessibility query, so a refresh that
    /// completes in under a second has always finished (and its control disappeared) by the time
    /// any query can observe it. A counter survives that; a transient view does not.
    /// See `PullToRefreshUITests`. DEBUG-only, so it can't exist in a shipped build.
    var refreshAllCount = 0
    #endif

    /// Everything a pull-to-refresh should pull. Every tab shares this rather than each one
    /// re-listing the subset it happens to display: what a person means by pulling down is "get
    /// me current", and being told that only Travel refreshes trips is not a distinction worth
    /// making them learn. It's user-initiated and infrequent, so the extra breadth is affordable
    /// in a way the automatic on-appear refreshes aren't.
    ///
    /// Unconditional by design — the `…IfNeeded` variants exist to keep automatic refreshes cheap,
    /// and reusing them here would make the gesture do nothing precisely when someone reaches for
    /// it because the screen looks stale.
    func refreshAll() async {
        #if DEBUG
        refreshAllCount += 1
        #endif
        // The only "…IfNeeded" that stays: its guard is `hasCouple`, not a staleness check, so
        // it already re-fetches every time it's called.
        //
        // For a couple it is also the *only* one of the four needed. `fetchCoupleState` already
        // returns trips, flights and memories — so pairing it with `refreshTrips`/`refreshFlights`
        // /`refreshMemories` fetched all three twice per pull, and signed every photo the couple
        // has ever added a second time along with them. Solo, it returns early on `hasCouple`,
        // and the individual refreshes are the only thing that fetches anything at all.
        async let coupleState: Void = refreshCoupleStateIfNeeded()
        async let trips: Void = hasCouple ? () : refreshTrips()
        async let flights: Void = hasCouple ? () : refreshFlights()
        async let memories: Void = hasCouple ? () : refreshMemories()
        async let decks: Void = refreshGameDecks()
        async let streak: Void = refreshDailyStreak()
        async let pads: Void = loadDrawingPads()
        _ = await (coupleState, trips, flights, memories, decks, streak, pads)
        if needsPartnerInvite {
            await refreshPendingConnectionRequests()
        }
    }

    /// Populates `gameDecks`/`deckProgress` once per app session (cheap to recheck — both are
    /// simple nil-guards) for the Games hub's topic list and progress bars.
    func loadGameDecksIfNeeded() async {
        guard gameDecks == nil else { return }
        await refreshGameDecks()
    }

    /// Re-fetches unconditionally — called after starting/resetting a deck session so its
    /// progress updates immediately rather than waiting for the next cold load.
    func refreshGameDecks() async {
        // Straight to the on-device catalogue when there's nothing to ask. Both fetches below take
        // a full URLSession timeout to fail offline, and the hub shows a spinner until they do —
        // a minute of waiting to be handed decks that were on the device the whole time.
        guard NetworkMonitor.shared.isConnected else {
            gameDecks = nonEmpty(GameContentStore.decks())
            gameDecksUnavailable = gameDecks?.isEmpty ?? true
            // Every topic bar on the hub is counted from this. Left nil it reads as zero decks
            // completed — telling a couple who has finished forty of them that they have finished
            // none, which is the same thing the streak used to do.
            if deckProgress == nil {
                deckProgress = OfflineGameStateCache.restore(for: BackendService.currentUserID)?.deckProgress
            }
            return
        }
        async let decks = BackendService.fetchGameDecks()
        async let progress = BackendService.fetchDeckProgress()
        let fetchedDecks = try? await decks
        // Falls back to the on-device catalogue rather than to nothing. Decks are the entry point
        // to every game, so with no network this was an empty hub — the screen a couple reaches
        // on the flight where they have hours and nothing else to do. `GameContentStore` carries
        // the same decks, from the bundled seed or from the last online refresh.
        gameDecks = fetchedDecks ?? nonEmpty(GameContentStore.decks())
        deckProgress = try? await progress
        if deckProgress != nil { recordGameStateForOffline() }
        // Distinguishes "haven't asked yet" from "asked and there's nothing to show", which
        // `gameDecks == nil` alone can't. Without it `RecommendedGamesSection` showed its loading
        // spinner forever whenever the fetch failed. Now that the fetch failing still leaves the
        // on-device catalogue, this is only true when *both* are empty — a failed fetch with decks
        // on disk isn't an unavailable state any more, it's just offline.
        // Deliberately not driven off `NetworkMonitor` alone: NWPathMonitor reports "connected" on
        // a captive portal or when the server itself is down, both of which strand the spinner
        // just the same.
        gameDecksUnavailable = gameDecks?.isEmpty ?? true
        // Detached, never awaited. This pulls the whole catalogue — four tables, ~2,000 rows, about
        // half a megabyte — and awaiting it here put all of that in front of the Games hub's first
        // paint, and in front of every `refreshAll()`. The decks it needs are already assigned
        // above; this only refreshes the offline copy for later, so nothing on screen is waiting
        // on it.
        Task.detached(priority: .background) { await Self.refreshGameContentIfStale() }
    }

    /// Empty means "the fetch produced nothing", which is not a usable fallback — keep nil so the
    /// caller can tell the difference.
    private func nonEmpty(_ decks: [GameDeck]) -> [GameDeck]? {
        decks.isEmpty ? nil : decks
    }

    /// Pulls the full deck-and-content catalogue onto the device so games work with no network.
    ///
    /// Daily, not per foreground: it's about half a megabyte, and content changes on the order of
    /// weeks. The first run after an install has no cached copy at all and fetches immediately —
    /// until then the app is running on the bundled seed, which is only as current as the last
    /// release.
    private static func refreshGameContentIfStale() async {
        guard NetworkMonitor.shared.isConnected else { return }
        if let age = GameContentStore.cacheAge, age < 24 * 60 * 60 { return }
        guard let payload = try? await BackendService.fetchGameContentPayload() else { return }
        GameContentStore.store(payload: payload)
    }

    /// Flips this deck's own "Your turn" → "Answered" bucket instantly, without waiting on
    /// `refreshGameDecks()`'s network round trip — called the moment `GameResultsView`/
    /// `GameCompletionView` appear, alongside (not instead of) that same refresh, which still
    /// runs to pick up the partner's own side. Without this, "Your turn" stayed stale for however
    /// long that fetch took, which read as "finishing a game doesn't count" until the user left
    /// and came back to the Games tab and the fetch had finally landed by then.
    func markDeckProgressMineCompleted(deckID: UUID?) {
        guard let deckID, var progress = deckProgress?[deckID] else { return }
        let wasCompleted = progress.bothCompleted
        progress.myAnswered = progress.totalRounds
        // My side being the one that finishes the deck makes *now* its completion moment — the
        // same stamp `advance_game_session_status` writes server-side. Without it the row keeps
        // whatever `completed_at`/`updated_at` the last fetch happened to carry, which sorted the
        // deck I just finished into the middle of the Answered list (and printed that stale date
        // on its card) until `refreshGameDecks()`' round trip landed.
        if !wasCompleted, progress.bothCompleted {
            progress.completedAt = .now
        }
        deckProgress?[deckID] = progress
    }

    /// All of this topic's decks, in curated order — Plus members see Premium-tier decks too now
    /// (they just show an unlock badge, see `isDeckLocked(_:)`), so this no longer filters by
    /// tier the way it originally did.
    func decks(for topic: GameTopic) -> [GameDeck] {
        (gameDecks ?? [])
            .filter { $0.topic == topic.rawValue }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// True if this deck requires a higher tier than the couple currently has — drives the
    /// unlock badge + premium-gate screen rather than hiding the deck outright.
    func isDeckLocked(_ deck: GameDeck) -> Bool {
        deck.tier == "premium" && subscriptionTier != "premium"
    }

    /// Same "Plus can see it exists, Premium unlocks it" shape as `isDeckLocked`, for
    /// non-deck features (e.g. the Flight Details screen's delay analysis/good-to-know/flight
    /// information cards) that are Premium-only but not backed by a `GameDeck` row.
    var isPremiumLocked: Bool {
        subscriptionTier != "premium"
    }

    /// Every deck of this game type, across every topic — powers "tap a game type card, see all
    /// its decks" browsing, as opposed to `decks(for topic:)`'s single-topic scoping.
    func decks(ofType gameType: GameType) -> [GameDeck] {
        (gameDecks ?? []).filter { $0.gameType == gameType }
    }

    /// How many of this topic's decks the couple has actually finished — `nil` until
    /// `loadGameDecksIfNeeded()` has completed.
    ///
    /// Counts completed decks rather than started ones. Started was doubly misleading: opening a
    /// deck creates its session before a single question is answered, so the bar crept up for
    /// decks nobody had played, and even a genuinely half-played deck read as full credit toward
    /// the topic.
    func topicProgress(_ topic: GameTopic) -> (played: Int, total: Int)? {
        guard gameDecks != nil else { return nil }
        let topicDecks = decks(for: topic)
        guard !topicDecks.isEmpty else { return nil }
        let progress = deckProgress ?? [:]
        let playedCount = topicDecks.filter { progress[$0.id]?.isCompleted ?? false }.count
        return (playedCount, topicDecks.count)
    }

    /// Only available once paired — there's no couple to namespace the storage path under
    /// beforehand, and no partner pad to make the feature meaningful yet.
    func saveMyDrawing(imageData: Data) async {
        guard let backendCoupleID else { return }
        let uploadedURL = try? await BackendService.uploadDrawingPad(coupleID: backendCoupleID, personID: currentUser.id, imageData: imageData)
        if let uploadedURL {
            // We already hold the bytes that were just uploaded, so put them in the disk cache
            // rather than making the next reader download what we just sent. This also keeps the
            // offline copy correct: without it, a save followed by going offline would show the
            // *previous* drawing back again, since that is what was still cached under this path.
            RemoteImageDiskCache.store(imageData, for: uploadedURL)
        }
        myDrawingURL = uploadedURL
        if uploadedURL != nil {
            Analytics.capture(Analytics.Event.doodleSave)
            Task { await BackendService.notifyPartner(event: .drawingSaved) }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        }
    }

    /// Serializing entry point — see `inFlightAdopt`'s doc comment for why this can't just be
    /// the function body directly. Each adopt waits for its predecessor, then runs.
    ///
    /// Chained rather than spun on. This used to be
    ///
    ///     while let inFlight = inFlightAdopt { await inFlight.value }
    ///
    /// which livelocks whenever two adopts overlap: the second reads the flag before the first has
    /// cleared it, awaits a task that has *already* finished, returns immediately, loops, and reads
    /// the same finished task again. On the main actor that is a spin, and the app sits on the
    /// splash screen forever — `restoreSession`'s `defer` never runs, so `isLoadingSession` never
    /// clears. Sampled in that state: 187 of 187 main-thread samples inside this loop.
    ///
    /// Two adopts overlap easily — `loadSignedInState` at launch and `refreshCoupleStateIfNeeded`
    /// on foreground both reach here — and the window is however long `performAdopt` takes.
    ///
    /// Holding the tail of a chain removes the loop entirely: waiting happens inside the new task,
    /// so there is no flag to re-read and nothing to clear. `inFlightAdopt` is only ever the most
    /// recently queued adopt, and each one releases its predecessor as it completes.
    private func adopt(_ state: BackendService.CoupleState) async {
        let previous = inFlightAdopt
        let task = Task { [weak self] () -> Void in
            await previous?.value
            await self?.performAdopt(state)
        }
        inFlightAdopt = task
        await task.value
    }

    /// Adopts real couple/trip/memory rows from the backend, flushing anything that was added
    /// locally before pairing completed (drafted during onboarding, or via the home screen's
    /// "add a trip"/"add a memory" cards while still solo).
    private func performAdopt(_ state: BackendService.CoupleState) async {
        let localOnlyTrips = trips.filter { pendingTripIDs.contains($0.id) }
        let localOnlyMemories = memories.filter { pendingMemoryIDs.contains($0.id) }

        couple = state.couple
        backendCoupleID = state.couple.id
        trips = state.trips
        memories = state.memories
        flights = state.flights
        // These three assignments replace the arrays wholesale, so an optimistic edit made while
        // the fetch was in the air is overwritten by the server's older copy. `refreshTrips`,
        // `refreshFlights` and `refreshMemories` have always reapplied here; this one never did,
        // and `refreshAll` only got away with it because it called those three afterwards and
        // they reapplied on its behalf. It no longer does — see `refreshAll`.
        reapplyInFlightMutations()
        Task { [weak self] in await self?.resolveMissingAirportTimezones() }
        partnerConnected = true
        hasCouple = true
        isSubscriptionActive = state.subscriptionActive
        subscriptionTier = state.subscriptionTier
        // The backend has just told us the couple-wide truth — remember it so a later cold launch
        // with no network doesn't fall back to `false` and paywall a real subscriber.
        OfflineSessionCache.record(
            active: state.subscriptionActive,
            tier: state.subscriptionTier,
            userID: BackendService.currentUserID,
            partnerConnected: true,
            myName: state.couple.partnerA.name,
            partnerName: state.couple.partnerB.name,
            celebrationShown: state.partnerConnectedCelebrationShown,
            checklistDismissed: state.setupChecklistDismissed
        )
        OfflineDataCache.record(
            trips: state.trips,
            flights: state.flights,
            memories: state.memories,
            myCity: state.couple.partnerA.homeCity,
            partnerCity: state.couple.partnerB.homeCity,
            myAvatarURL: state.couple.partnerA.avatarURL,
            partnerAvatarURL: state.couple.partnerB.avatarURL,
            couple: state.couple,
            userID: BackendService.currentUserID
        )
        prefetchMemoryPhotos()
        // Adoption is the only thing that sets `backendCoupleID`, and the drawing pads are the one
        // part of Home whose contents it does *not* hand over — trips, memories and flights all
        // arrive in `state`, so they survive being fetched too early; the pads are two signed URLs
        // that have to be asked for separately, behind a `guard let backendCoupleID`. Every caller
        // raced that guard: `refreshAll` starts `loadDrawingPads()` with `async let` alongside the
        // couple fetch that sets the ID, and both `.task` sites fire when their view appears. A
        // loss is permanent, because nothing re-runs it — so the pads stayed blank for the whole
        // session. Kicking it off here means the fetch happens *because* the ID now exists.
        //
        // NOT awaited. The ID it needs is already set, so a detached task sees it — and awaiting
        // put two signed-URL round trips on the launch path, inside the adopt that everything else
        // serializes behind. Nothing on screen waits for a pad URL; the splash screen was waiting
        // for both of them.
        Task { [weak self] in await self?.loadDrawingPads() }
        partnerConnectedCelebrationShown = state.partnerConnectedCelebrationShown
        setupChecklistDismissed = state.setupChecklistDismissed
        noteCurrentDistanceIfRecord()

        var stillPendingTrips = Set<Trip.ID>()
        for trip in localOnlyTrips {
            // Trips drafted before pairing (e.g. onboarding's "add first flight") were built
            // against a placeholder partner id that never existed as a real profile — remap
            // to the now-real partner so the FK on `trips.traveler_ids` doesn't reject it. A
            // self-tagged id already matches the real partnerA (see `addTrip`) and is left
            // untouched; only an unmatched (placeholder) id gets remapped, so a "Both" trip's
            // two ids are each handled independently rather than the whole array being replaced.
            var tripToInsert = trip
            tripToInsert.travelerIDs = tripToInsert.travelerIDs.map { id in
                (id == state.couple.partnerA.id || id == state.couple.partnerB.id) ? id : state.couple.partnerB.id
            }
            do {
                try await BackendService.insertTrip(coupleID: state.couple.id, trip: tripToInsert)
                // Now durably on the backend — the local disk copy was only ever a stand-in
                // until this succeeded.
                PendingTripStore.remove(id: trip.id)
            } catch {
                stillPendingTrips.insert(trip.id)
            }
            trips.append(tripToInsert)
        }
        pendingTripIDs = stillPendingTrips

        // Attach any flight picked alongside a pre-pairing trip, now that the trip it belongs to
        // is guaranteed to exist server-side (either just inserted above, or synced in an earlier
        // `performAdopt` call whose flight-add attempt failed and is retried here). Left queued
        // on failure so the next `performAdopt` retries it; skipped entirely for a trip that's
        // still pending, since `AeroFlightService.addFlight`'s trip FK would just reject it.
        var didAttachPendingFlight = false
        for (tripID, pending) in pendingFlightCandidates where !stillPendingTrips.contains(tripID) {
            // Per-leg, so a multi-leg itinerary where one leg's add fails still attaches the rest
            // and only re-queues what didn't land. Dropping the whole trip's flights over a single
            // failed leg would be a worse outcome than a partially-attached itinerary the next
            // adopt finishes off.
            var unattached: [AeroFlightCandidate] = []
            for candidate in pending.candidates {
                if (try? await AeroFlightService.addFlight(candidate: candidate, tripID: tripID, travelerIDs: pending.travelerIDs, notifyMe: true)) != nil {
                    didAttachPendingFlight = true
                } else {
                    unattached.append(candidate)
                }
            }
            if unattached.isEmpty {
                pendingFlightCandidates.removeValue(forKey: tripID)
            } else {
                pendingFlightCandidates[tripID] = (unattached, pending.travelerIDs)
            }
        }
        if didAttachPendingFlight {
            await refreshFlights()
        }

        var stillPendingMemories = Set<Memory.ID>()
        for memory in localOnlyMemories {
            var synced = memory
            do {
                var photoPaths: [String] = []
                for imageData in pendingMemoryPhotoData[memory.id] ?? [] {
                    photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: state.couple.id, memoryID: memory.id, imageData: imageData))
                }
                synced.photos = try await BackendService.insertMemory(coupleID: state.couple.id, memory: memory, photoPaths: photoPaths)
                pendingMemoryPhotoData.removeValue(forKey: memory.id)
                // Now durably on the backend — the local disk copy (and its cached photo
                // files) was only ever a stand-in until this succeeded.
                PendingMemoryStore.remove(id: memory.id)
            } catch {
                stillPendingMemories.insert(memory.id)
            }
            memories.append(synced)
        }
        pendingMemoryIDs = stillPendingMemories
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        await startFlightsRealtimeSubscription(coupleID: state.couple.id)
    }

    /// Opportunistic persistence for the Stats tab's "Longest distance between" milestone — fires
    /// every time fresh couple state loads (this runs from `performAdopt`, itself called on every
    /// foreground refresh), which is exactly when both partners' home cities are known to be
    /// current. Only calls the backend when today's distance would actually raise the stored
    /// record, both to avoid a pointless network call on every refresh and because the RPC's own
    /// `GREATEST` is a safety net for races, not something to lean on for the common case.
    private func noteCurrentDistanceIfRecord() {
        guard let mine = couple.partnerA.homeCity?.coordinate, let theirs = couple.partnerB.homeCity?.coordinate else { return }
        let currentKm = Geo.distanceKm(mine, theirs)
        guard currentKm > (couple.maxDistanceKm ?? 0) else { return }
        let coupleID = couple.id
        Task { try? await BackendService.updateCoupleMaxDistance(coupleID: coupleID, distanceKm: currentKm) }
    }

    /// Idempotent — safe to call even if a subscription for this exact couple is already
    /// running. `performAdopt` runs on every foreground refresh (from both `HomeView` and
    /// `RootView`'s scenePhase handlers), so this fires far more often than a couple actually
    /// changes; skipping the no-op case isn't just an optimization. Tearing down and
    /// resubscribing on every call used to race: `stopFlightsRealtimeSubscription` unsubscribed
    /// the old channel fire-and-forget (not awaited) while `supabase.channel(_:)` for the new
    /// one reused the *same* topic string — if the SDK's registry hadn't finished removing the
    /// old channel yet, `.channel(_:)` handed back that same still-subscribed instance, and
    /// adding `postgresChange` callbacks to an already-subscribed channel threw "Cannot add
    /// postgres_changes callbacks... after subscribe()". Awaiting the teardown before creating
    /// the replacement (for the rare real couple-switch case) closes that race.
    private func startFlightsRealtimeSubscription(coupleID: UUID) async {
        guard flightsRealtimeCoupleID != coupleID else { return }
        await stopFlightsRealtimeSubscription()
        let (channel, stream) = BackendService.subscribeToCoupleFlights(coupleID: coupleID)
        flightsRealtimeChannel = channel
        flightsRealtimeCoupleID = coupleID
        flightsRealtimeTask = Task { [weak self] in
            for await _ in stream {
                await self?.refreshFlights()
            }
        }
    }

    private func stopFlightsRealtimeSubscription() async {
        flightsRealtimeTask?.cancel()
        flightsRealtimeTask = nil
        if let flightsRealtimeChannel {
            await BackendService.unsubscribe(flightsRealtimeChannel)
        }
        flightsRealtimeChannel = nil
        flightsRealtimeCoupleID = nil
    }

    /// Called once account creation succeeds — now happens *before* the paywall/trial screens
    /// rather than after, so a real account exists to tie the subscription to. Persists
    /// everything collected during the default onboarding flow (situation/frequency/
    /// attribution/goals go to PostHog as person properties via `Analytics.setOnboardingTraits`,
    /// not Supabase — they're analytics-segmentation traits, not app data anything else reads;
    /// names/cities/photos/drafted flight apply here) — nothing could be written to Supabase
    /// before a session existed. Deliberately does **not** set `hasCouple = true`: `RootView` swaps
    /// straight to `MainTabView` the instant that flips, which would skip the paywall/trial
    /// screens still left to show. `finishOnboarding()` does that final flip once they're done.
    ///
    /// If a real couple already exists (the partner redeemed an invite in a race, or this is
    /// the preserved deep-link path resuming a session that already finished pairing), there's
    /// nothing left to onboard, so this does finish immediately — a narrow edge case where a
    /// returning user skips straight past the paywall.
    func applyOnboardingAccount(_ onboarding: OnboardingModel) async {
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
            inviteCode = onboarding.inviteCode
            hasCouple = true
            return
        }

        if let userID = BackendService.currentUserID {
            adoptSignedInIdentity(id: userID, firstName: onboarding.firstName)
            // The device's push token typically arrives at launch, well before this signup
            // completes and `currentUserID` becomes valid — `registerPushToken` would have
            // silently cached it rather than dropped it (see `pendingPushTokenData`'s own doc
            // comment), but nothing flushed that cache for a fresh signup completed in one
            // continuous onboarding session (no relaunch, no `SignInView`). Without this, that
            // device never gets a `device_push_tokens` row until the next cold launch.
            await retryPendingPushTokenRegistrationIfNeeded()
            Analytics.setOnboardingTraits(
                userID: userID,
                attribution: onboarding.attribution,
                situation: onboarding.situation,
                frequency: onboarding.frequency,
                goals: onboarding.goals,
                userGender: onboarding.userGender,
                partnerGender: onboarding.partnerGender
            )
        }

        if let selfPhotoData = onboarding.selfPhotoData,
           let url = try? await BackendService.uploadAvatar(imageData: selfPhotoData) {
            AvatarView.preloadCache(imageData: selfPhotoData, url: url)
            couple.partnerA.avatarURL = url
        }
        if let partnerPhotoData = onboarding.partnerPhotoData,
           let url = try? await BackendService.uploadPartnerAvatar(imageData: partnerPhotoData) {
            AvatarView.preloadCache(imageData: partnerPhotoData, url: url)
            couple.partnerB.avatarURL = url
        }

        if let homeCity = onboarding.homeCity {
            try? await BackendService.updateHomeCity(homeCity)
            couple.partnerA.homeCity = homeCity
        }

        if !onboarding.partnerName.isEmpty {
            try? await BackendService.updatePartnerNickname(onboarding.partnerName)
            couple.partnerB.name = onboarding.partnerName
        }
        if let partnerCity = onboarding.partnerCity {
            try? await BackendService.updatePartnerHomeCityGuess(partnerCity)
            couple.partnerB.homeCity = partnerCity
        }

        if let anniversaryDate = onboarding.anniversaryDate {
            try? await BackendService.updateAnniversaryDate(anniversaryDate)
            couple.startedDatingOn = anniversaryDate
        }

        inviteCode = onboarding.inviteCode
    }

    /// The actual last step of onboarding — called once the paywall/trial flow finishes, so
    /// `RootView` lands the user in `MainTabView`. Account creation already happened earlier
    /// via `applyOnboardingAccount`.
    func finishOnboarding() {
        hasCouple = true
    }

    /// Creates a trip with no flight attached — flights are never self-reported (see
    /// `AeroFlightService.addFlight`/`LiveActivityManager`); callers that have a real,
    /// AeroAPI-resolved `AeroFlightCandidate` in hand should pass it as `flightCandidate` rather
    /// than calling `AeroFlightService.addFlight` themselves — when there's no couple yet (e.g.
    /// onboarding's "add our next trip" step, before pairing), that call would fail outright
    /// since the trip doesn't exist server-side yet. Passing it through here instead queues it
    /// in `pendingFlightCandidates`, so `performAdopt(_:)` can attach it once the trip is
    /// actually inserted — previously it was just silently dropped.
    @discardableResult
    /// `flightCandidates` is a list because a trip's itinerary genuinely is one — a connecting
    /// journey is two or more separately-tracked flights, and `Trip.flights` has always modelled
    /// that. Only trip *creation* accepted a single flight; `TripDetailsView`'s "Link another leg"
    /// could add the rest afterwards, which made attaching a second leg a thing you had to know to
    /// go back and do. Legs attach independently — one failing doesn't discard the others.
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, category: TripCategory, flightCandidates: [AeroFlightCandidate] = []) async -> Trip {
        let travelerIDs: [Person.ID] = {
            switch traveler {
            case .you: return [currentUser.id]
            case .partner: return [partner.id]
            case .both: return [currentUser.id, partner.id]
            }
        }()
        let distance = Geo.distanceKm(origin.coordinate, destination.coordinate)

        let trip = Trip(
            travelerIDs: travelerIDs,
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            category: category,
            distanceKm: distance
        )

        trips.append(trip)
        checkReviewMilestones()
        Analytics.capture(Analytics.Event.tripCreate, properties: ["trip_category": category.analyticsValue])

        if let backendCoupleID {
            do {
                try await BackendService.insertTrip(coupleID: backendCoupleID, trip: trip)
                // A schedule-only candidate (no faFlightId yet — see AeroFlightCandidate.canTrack)
                // still gets persisted as a pending flight — add-flight accepts it without one and
                // refresh-due-flights' cron backfills a real faFlightId (and starts live tracking)
                // automatically once AeroAPI assigns this flight one.
                var attached = false
                var unattached: [AeroFlightCandidate] = []
                for candidate in flightCandidates {
                    if (try? await AeroFlightService.addFlight(candidate: candidate, tripID: trip.id, travelerIDs: travelerIDs, notifyMe: true)) != nil {
                        attached = true
                    } else {
                        unattached.append(candidate)
                    }
                }
                if attached { await refreshFlights() }
                if !unattached.isEmpty { pendingFlightCandidates[trip.id] = (unattached, travelerIDs) }
            } catch {
                pendingTripIDs.insert(trip.id)
                PendingTripStore.save(trip)
                if !flightCandidates.isEmpty {
                    pendingFlightCandidates[trip.id] = (flightCandidates, travelerIDs)
                }
            }
        } else {
            pendingTripIDs.insert(trip.id)
            PendingTripStore.save(trip)
            if !flightCandidates.isEmpty {
                pendingFlightCandidates[trip.id] = (flightCandidates, travelerIDs)
            }
        }

        return trip
    }

    /// Re-pulls the full flight list from the backend — called after the Add Flight search
    /// flow resolves a real AeroAPI-tracked flight (via the `add-flight` Edge Function, which
    /// writes the row server-side, so there's nothing to merge locally) and by
    /// `FlightDetailView` after an on-demand refresh.
    func refreshFlights() async {
        guard let backendCoupleID else { return }
        if let fresh = try? await BackendService.fetchFlights(coupleID: backendCoupleID) {
            flights = fresh
            for index in trips.indices {
                trips[index].flights = fresh.filter { $0.tripID == trips[index].id }
            }
            await resolveMissingAirportTimezones()
            reapplyInFlightMutations()
            await LiveActivityManager.shared.reconcileOnLaunch(with: fresh)
            await LiveActivityManager.shared.syncActivities(
                for: fresh,
                participants: { [weak self] flight in
                    guard let self else { return JourneyParticipants(travelerName: "", partnerName: "", viewerIsTraveler: false) }
                    // Who's flying — not whether it's a reunion. These were the same call until
                    // the split above.
                    let partnerIsTravelling = isPartnerTravelling(flight)
                    return JourneyParticipants(
                        travelerName: partnerIsTravelling ? partner.name : currentUser.name,
                        partnerName: partnerIsTravelling ? currentUser.name : partner.name,
                        viewerIsTraveler: !partnerIsTravelling
                    )
                },
                isReunion: isReunion
            )
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
            checkReviewMilestones()
        }
    }

    /// Fills in airport timezones the backend didn't supply.
    ///
    /// A flight that came from AeroAPI's `/schedules` endpoint — anything booked more than about
    /// two days ahead — has no timezone on either airport, because that endpoint returns bare
    /// origin/destination codes with no airport object behind them. `add-flight` looks it up in the
    /// `airports` table when the row is created, and a migration fills in the rows written before
    /// it did, but neither helps a device running against a backend where those have not been
    /// deployed yet, and neither covers an airport missing from the reference table entirely.
    ///
    /// Without a zone, every screen falls back to something — and they don't all fall back to the
    /// same thing, which is how one departure read 4:20pm in the summary and 8:20am in the detail
    /// card. So the app resolves it too, from the same table, in one query for everything it is
    /// missing. Silent and best-effort: a flight whose airport genuinely isn't in the table keeps
    /// falling back, as it did before.
    func resolveMissingAirportTimezones() async {
        var needed = Set<String>()
        for flight in flights {
            if flight.origin.timezone == nil, let code = flight.origin.iata, !code.isEmpty { needed.insert(code) }
            if flight.destination.timezone == nil, let code = flight.destination.iata, !code.isEmpty { needed.insert(code) }
        }
        guard !needed.isEmpty else { return }

        await AirportTimeZoneResolver.resolve(iataCodes: Array(needed))

        var changed = false
        for index in flights.indices {
            if flights[index].origin.timezone == nil,
               let zone = AirportTimeZoneResolver.timeZone(forIATACode: flights[index].origin.iata) {
                flights[index].origin.timezone = zone.identifier
                changed = true
            }
            if flights[index].destination.timezone == nil,
               let zone = AirportTimeZoneResolver.timeZone(forIATACode: flights[index].destination.iata) {
                flights[index].destination.timezone = zone.identifier
                changed = true
            }
        }
        guard changed else { return }
        // Trips carry their own copies of the same flights; a trip's flight list left un-updated
        // would show the old fallback time beside the corrected one.
        for index in trips.indices {
            trips[index].flights = flights.filter { $0.tripID == trips[index].id }
        }
    }

    /// Re-pulls the full memory list from the backend — same purpose as `refreshFlights()`
    /// above. Without this, a partner's newly-added memory only ever appeared after a full
    /// couple-state reload (effectively just app relaunch), since `memories` was otherwise only
    /// ever bulk-populated once at adopt time and mutated locally by this device's own edits.
    func refreshMemories() async {
        guard let backendCoupleID else { return }
        if let fresh = try? await BackendService.fetchMemories(coupleID: backendCoupleID) {
            memories = fresh
            reapplyInFlightMutations()
        }
    }

    /// Re-pulls the full trip list from the backend — same purpose/gap as `refreshMemories()`
    /// above. Flight linkage is filled in from whatever's already in `flights` immediately (in
    /// case `refreshFlights()` isn't also called this cycle), then `refreshFlights()` — called
    /// alongside this everywhere it matters — re-links authoritatively from the fetched flight
    /// rows regardless of call order.
    func refreshTrips() async {
        guard let backendCoupleID else { return }
        if var fresh = try? await BackendService.fetchTrips(coupleID: backendCoupleID) {
            for index in fresh.indices {
                fresh[index].flights = flights.filter { $0.tripID == fresh[index].id }
            }
            trips = fresh
            reapplyInFlightMutations()
        }
    }

    /// Stops tracking a flight entirely (swipe-to-remove or bulk-select-delete on the Trips tab).
    /// Removed from `flights` immediately for a snappy swipe/bulk-delete (same optimistic-removal
    /// shape as `deleteTrip`) — `refreshFlights()` still runs afterward rather than trusting that
    /// local removal alone, since its Live Activity sync/reconcile logic there already ends an
    /// Activity for any flight that disappeared from the fetched list, and this reuses that
    /// cleanup rather than duplicating it here.
    func deleteFlight(_ flight: Flight) async {
        flights.removeAll { $0.id == flight.id }
        for index in trips.indices {
            trips[index].flights.removeAll { $0.id == flight.id }
        }
        Analytics.capture(Analytics.Event.flightDelete)
        try? await BackendService.deleteFlight(id: flight.id)
        await refreshFlights()
    }

    /// Bulk-delete entry point for the Trips tab's flight multi-select mode — sequential, not
    /// concurrent, same reasoning as `deleteMemories`: `deleteFlight` mutates `flights` in place
    /// and `AppModel` isn't actor-isolated, so running many deletes at once would race on that
    /// array. A handful of sequential deletes is fast enough that this isn't a real latency
    /// concern.
    func deleteFlights(_ flightsToDelete: [Flight]) async {
        for flight in flightsToDelete {
            await deleteFlight(flight)
        }
    }

    /// Whose flight this is — the partner's whenever the signed-in user isn't the one who
    /// added/is tracking it. Defaults to true when `createdBy` is unset (e.g. an older row) since
    /// most tracked flights are the partner's. Only decides *whose name* the Live Activity shows;
    /// deliberately separate from `isReunion` below, which the same check used to do double duty
    /// for.
    /// Who is actually on the plane, which is not the same question as who typed it in.
    ///
    /// `travelerIDs` is the answer whenever it has one — it is set explicitly on the confirmation
    /// step, and it is the only field that knows a person added a flight *for* their partner.
    /// `createdBy` is the fallback for flights saved before that was asked, and for a flight where
    /// both of them are travelling the viewer counts as travelling too.
    private func isPartnerTravelling(_ flight: Flight) -> Bool {
        if !flight.travelerIDs.isEmpty {
            return !flight.travelerIDs.contains(currentUser.id)
        }
        guard let createdBy = flight.createdBy else { return true }
        return createdBy != currentUser.id
    }

    /// Whether this flight is actually closing the distance — true only when it belongs to a trip
    /// explicitly categorised as a reunion, matching how `WidgetSnapshotWriter` already derives
    /// `isReunionTrip`.
    ///
    /// This used to be "the partner added it", which conflated *who is flying* with *where they're
    /// flying to*: a partner's work trip or family visit got the same "on the way to you ❤️"
    /// framing as them actually coming to see you. A flight with no linked trip can't be marked as
    /// anything, so it isn't a reunion either.
    private func isReunion(_ flight: Flight) -> Bool {
        guard let tripID = flight.tripID,
              let trip = trips.first(where: { $0.id == tripID }) else { return false }
        return trip.category == .reunion
    }

    /// Freeform trip prep notes — reused by the Flight Detail screen's "Trip checklist" card
    /// rather than inventing a separate checklist feature/table.
    func updateTripNotes(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index].notes = trip.notes
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.trips.firstIndex(where: { $0.id == trip.id }) else { return }
            self.trips[index].notes = trip.notes
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.updateTripNotes(tripID: trip.id, notes: trip.notes)
    }

    /// Full edit of a trip's own fields (origin/destination/dates/category/notes) — as opposed
    /// to `updateTripNotes`, which only ever touched notes. Recomputes `distanceKm` since
    /// either city could have changed, and preserves the trip's linked flights (not part of what
    /// this edits).
    func updateTrip(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        updated.distanceKm = Geo.distanceKm(trip.origin.coordinate, trip.destination.coordinate)
        updated.flights = trips[index].flights
        trips[index] = updated
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.trips.firstIndex(where: { $0.id == trip.id }) else { return }
            var reapplied = updated
            reapplied.flights = self.trips[index].flights
            self.trips[index] = reapplied
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.updateTrip(updated)
    }

    func deleteTrip(_ trip: Trip) async {
        // Captured before the removal below so a failed delete can put both back exactly as
        // they were, rather than leaving the trip permanently gone from the UI while the row
        // still exists server-side.
        let affectedFlightIDs = Set(flights.filter { $0.tripID == trip.id }.map(\.id))
        trips.removeAll { $0.id == trip.id }
        pendingTripIDs.remove(trip.id)
        PendingTripStore.remove(id: trip.id)
        pendingFlightCandidates.removeValue(forKey: trip.id)
        Analytics.capture(Analytics.Event.tripDelete)
        // `flights.trip_id` has ON DELETE SET NULL server-side — every leg survives untethered
        // (there can be more than one), so mirror that locally rather than leaving any of them
        // pointing at a trip that no longer exists.
        for index in flights.indices where flights[index].tripID == trip.id {
            flights[index].tripID = nil
        }
        guard backendCoupleID != nil else { return }
        do {
            try await BackendService.deleteTrip(id: trip.id)
        } catch {
            // The delete didn't actually happen — restore rather than leave the user believing
            // it succeeded while the trip (and its flights' linkage) still exists server-side.
            trips.append(trip)
            for index in flights.indices where affectedFlightIDs.contains(flights[index].id) {
                flights[index].tripID = trip.id
            }
            syncTripFlights(tripID: trip.id)
        }
    }

    /// Bulk-delete entry point for the Trips tab's trip multi-select mode — same sequential
    /// reasoning as `deleteMemories`/`deleteFlights`.
    func deleteTrips(_ tripsToDelete: [Trip]) async {
        for trip in tripsToDelete {
            await deleteTrip(trip)
        }
    }

    /// Keeps `trips[tripID].flights` consistent with the authoritative `flights` array after any
    /// local mutation to a flight's `tripID`/fields — recomputed fresh from `flights` rather than
    /// patched in place, so it's correct regardless of how many legs that trip has.
    private func syncTripFlights(tripID: UUID) {
        guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[tripIndex].flights = flights.filter { $0.tripID == tripID }
    }

    /// Attaches an already-tracked flight to a trip — a trip can have more than one (e.g. a
    /// connecting itinerary tracked as separate legs), so this adds rather than replaces. Every
    /// other write path for `flight.tripID` (`AeroFlightService.addFlight`) only ever sets it
    /// once, at add-flight time.
    func linkFlight(_ flight: Flight, to trip: Trip) async {
        guard let flightIndex = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[flightIndex].tripID = trip.id
        syncTripFlights(tripID: trip.id)
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.flights.firstIndex(where: { $0.id == flight.id }) else { return }
            self.flights[index].tripID = trip.id
            self.syncTripFlights(tripID: trip.id)
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.setFlightTrip(flightID: flight.id, tripID: trip.id)
    }

    func unlinkFlight(_ flight: Flight) async {
        guard let flightIndex = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        let tripID = flights[flightIndex].tripID
        flights[flightIndex].tripID = nil
        if let tripID { syncTripFlights(tripID: tripID) }
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.flights.firstIndex(where: { $0.id == flight.id }) else { return }
            self.flights[index].tripID = nil
            if let tripID { self.syncTripFlights(tripID: tripID) }
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.setFlightTrip(flightID: flight.id, tripID: nil)
    }

    /// Same gap `linkFlight`/`unlinkFlight` closed for `tripID` — travelers were also only ever
    /// set once, at add-flight time, with no way to change them afterward. Pass an empty array
    /// to clear (e.g. neither partner is confirmed as the traveler yet); pass both ids when
    /// they're travelling together.
    func setFlightTravelers(_ flight: Flight, travelerIDs: [UUID]) async {
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[index].travelerIDs = travelerIDs
        if let tripID = flights[index].tripID { syncTripFlights(tripID: tripID) }
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.flights.firstIndex(where: { $0.id == flight.id }) else { return }
            self.flights[index].travelerIDs = travelerIDs
            if let tripID = self.flights[index].tripID { self.syncTripFlights(tripID: tripID) }
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.setFlightTravelers(flightID: flight.id, travelerIDs: travelerIDs)
    }

    /// Memories have no automatic trip association (no place/date matching) — linking is
    /// always this explicit, user-driven action from Trip Details.
    func linkMemory(_ memory: Memory, to trip: Trip) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].tripID = trip.id
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.memories.firstIndex(where: { $0.id == memory.id }) else { return }
            self.memories[index].tripID = trip.id
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.setMemoryTrip(memoryID: memory.id, tripID: trip.id)
    }

    func unlinkMemory(_ memory: Memory) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].tripID = nil
        let mutationID = trackInFlightMutation { [weak self] in
            guard let self, let index = self.memories.firstIndex(where: { $0.id == memory.id }) else { return }
            self.memories[index].tripID = nil
        }
        defer { clearInFlightMutation(mutationID) }
        try? await BackendService.setMemoryTrip(memoryID: memory.id, tripID: nil)
    }

    /// Registers this device's APNs token against the signed-in profile so
    /// `send-flight-notification` (server-side) has somewhere to deliver to. Safe to call
    /// repeatedly — the backend upserts on the token itself.
    /// Cached raw APNs token bytes, kept around until a registration attempt actually succeeds.
    /// `didRegisterForRemoteNotificationsWithDeviceToken` can fire before `restoreSession()`'s
    /// async `supabase.auth.session` restore has finished — `BackendService.registerDeviceToken`
    /// requires `currentUserID`, so a registration attempt that loses that race throws
    /// `.notAuthenticated` and (since the call site swallows it with `try?`) silently drops the
    /// token for the rest of that launch, with nothing anywhere to indicate it happened. Real
    /// symptom this caused: a signed-in couple with notifications genuinely enabled on-device,
    /// backend sends reporting success, and zero pushes ever arriving — the row in
    /// `device_push_tokens` was simply stale or missing. `loadSignedInState()` retries this once
    /// a session is confirmed, closing the race regardless of which order the two async events
    /// actually finish in.
    private var pendingPushTokenData: Data?

    /// The hex token last successfully registered — kept around purely so `signOut()` has
    /// something to unregister (see `BackendService.unregisterDeviceToken`'s own doc comment).
    /// `pendingPushTokenData` isn't a substitute for this: it's cleared to `nil` the moment
    /// registration succeeds, which is exactly when this needs to start holding a value.
    private var lastRegisteredPushTokenHex: String?

    func registerPushToken(_ tokenData: Data) async {
        pendingPushTokenData = tokenData
        await retryPendingPushTokenRegistrationIfNeeded()
    }

    func retryPendingPushTokenRegistrationIfNeeded() async {
        guard let tokenData = pendingPushTokenData else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await BackendService.registerDeviceToken(token, environment: environment)
            pendingPushTokenData = nil
            lastRegisteredPushTokenHex = token
        } catch {
            // Most likely still not authenticated yet — leave it cached so the next
            // `loadSignedInState()` (or another `registerPushToken` call) can retry.
        }
    }

    @discardableResult
    func addMemory(title: String, place: Place?, date: Date, note: String, imagesData: [Data]) async -> Memory {
        let memory = Memory(title: title, place: place, date: date, note: note)
        Analytics.capture(Analytics.Event.memoryCreate, properties: ["photo_count": imagesData.count])

        guard let backendCoupleID else {
            // Persisted to disk (not just kept in memory) — this is the only durable copy
            // until a partner joins, and the returned memory's photos already point at local
            // files so they show immediately instead of staying blank until upload.
            let persisted = PendingMemoryStore.save(memory: memory, photosData: imagesData)
            memories.append(persisted)
            pendingMemoryIDs.insert(persisted.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[persisted.id] = imagesData }
            checkReviewMilestones()
            return persisted
        }

        memories.append(memory)
        checkReviewMilestones()

        do {
            var photoPaths: [String] = []
            for imageData in imagesData {
                photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
            }
            let photos = try await BackendService.insertMemory(coupleID: backendCoupleID, memory: memory, photoPaths: photoPaths)
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index].photos = photos
            }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        } catch {
            pendingMemoryIDs.insert(memory.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[memory.id] = imagesData }
        }

        return memories.first { $0.id == memory.id } ?? memory
    }

    /// Edits an existing memory's fields in place, optionally appending new photos in the
    /// same call — both persisted best-effort, matching `addMemory`'s error handling.
    func updateMemory(_ memory: Memory, newImagesData: [Data] = []) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }

        guard let backendCoupleID, !pendingMemoryIDs.contains(memory.id) else {
            // Still pending (never synced) — everything happens locally, same as the initial
            // add: new photos join the accumulated pending data and get re-persisted, so the
            // edit shows immediately and survives a relaunch. Without this, editing a pending
            // memory before a partner joins silently dropped any newly-added photos (the
            // synced-path branch below only uploads when a couple already exists) and never
            // updated the on-disk copy, so the *previous* version would come back after a kill.
            var accumulatedPhotoData = pendingMemoryPhotoData[memory.id] ?? []
            accumulatedPhotoData.append(contentsOf: newImagesData)
            let persisted = PendingMemoryStore.save(memory: memory, photosData: accumulatedPhotoData)
            memories[index] = persisted
            pendingMemoryPhotoData[memory.id] = accumulatedPhotoData.isEmpty ? nil : accumulatedPhotoData
            return
        }

        memories[index] = memory

        do {
            try await BackendService.updateMemory(memory)
            if !newImagesData.isEmpty {
                var photoPaths: [String] = []
                for imageData in newImagesData {
                    photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
                }
                let newPhotos = try await BackendService.addMemoryPhotos(memoryID: memory.id, photoPaths: photoPaths, startingPosition: memory.photos.count)
                memories[index].photos.append(contentsOf: newPhotos)
            }
        } catch {
            // Best-effort for now; local edit stands even if the write failed.
        }
    }

    func removePhoto(_ photo: MemoryPhoto, from memory: Memory) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].photos.removeAll { $0.id == photo.id }

        guard !pendingMemoryIDs.contains(memory.id) else {
            // Re-derive the remaining photo bytes from their still-valid local files and
            // re-persist — otherwise a removed photo could reappear on the next pending edit
            // (updateMemory would still find it in the stale pendingMemoryPhotoData) or after
            // a relaunch (the on-disk manifest would still list it).
            let remainingData = memories[index].photos.compactMap { try? Data(contentsOf: $0.url) }
            let persisted = PendingMemoryStore.save(memory: memories[index], photosData: remainingData)
            memories[index] = persisted
            pendingMemoryPhotoData[memory.id] = remainingData.isEmpty ? nil : remainingData
            return
        }

        try? await BackendService.deleteMemoryPhoto(id: photo.id, path: photo.path)
    }

    func deleteMemory(_ memory: Memory) async {
        memories.removeAll { $0.id == memory.id }
        pendingMemoryIDs.remove(memory.id)
        pendingMemoryPhotoData.removeValue(forKey: memory.id)
        PendingMemoryStore.remove(id: memory.id)
        Analytics.capture(Analytics.Event.memoryDelete)
        guard backendCoupleID != nil else { return }
        do {
            try await BackendService.deleteMemory(id: memory.id, photoPaths: memory.photos.map(\.path))
        } catch {
            // The delete didn't actually happen — restore rather than leave the user believing
            // it succeeded while the memory still exists server-side.
            memories.append(memory)
        }
    }

    /// Bulk-delete entry point for Memories' multi-select mode — sequential, not concurrent:
    /// `deleteMemory` mutates `memories` in place and `AppModel` isn't actor-isolated, so running
    /// many deletes at once would race on that array. A handful of sequential deletes is fast
    /// enough that this isn't a real latency concern.
    func deleteMemories(_ memoriesToDelete: [Memory]) async {
        for memory in memoriesToDelete {
            await deleteMemory(memory)
        }
    }

    /// Only ever writes the signed-in user's own city — RLS blocks updating a partner's
    /// profile row, so there's no "set it on their behalf" path anymore.
    func setHomeCity(for personID: Person.ID, city: Place) async {
        guard personID == currentUser.id else { return }
        do {
            try await BackendService.updateHomeCity(city)
            couple.partnerA.homeCity = city
        } catch {
            // Best-effort for now; the picker just won't reflect the change.
        }
    }

    /// `RootView`'s foreground-triggered current-city refresh lands here once
    /// `HomeLocationService` resolves a fresh fix — compares by city/country name, not
    /// `Place.id`, since a new location fix builds a brand new `Place` (fresh random id) on
    /// every call even when the resolved city hasn't actually changed, and an id comparison
    /// would rewrite the backend row (and spuriously invalidate `HomeView`'s per-city-id weather
    /// cache) on every single foreground for no reason.
    func updateCurrentCityIfChanged(_ place: Place) async {
        guard place.city != couple.partnerA.homeCity?.city || place.country != couple.partnerA.homeCity?.country else { return }
        await setHomeCity(for: currentUser.id, city: place)
    }

    /// Sets the signed-in user's identity as soon as an account exists, so any trip drafted
    /// during the rest of onboarding (before pairing) carries the real profile id rather
    /// than a throwaway placeholder.
    func adoptSignedInIdentity(id: UUID, firstName: String) {
        couple.partnerA = Person(
            id: id,
            name: firstName.isEmpty ? "You" : firstName,
            homeCity: couple.partnerA.homeCity,
            accentColor: Person.palette[1]
        )
    }
}
