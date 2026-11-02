//
//  TravelStore.swift
//  Twofold
//
//  The couple's trips, flights and memories: what is on screen, what is still waiting to be
//  created, the flights realtime channel and the Live Activity sync, and every add, edit, link and
//  delete. Owned by `AppModel`, which forwards the old names to it.
//
//  What it needs from the rest of the app — the account generation, the couple id, who is who, the
//  outbox — it reads through `TravelStoreHost`, which `AppModel` is.
//

import Foundation
import Observation
import Supabase

/// What `TravelStore` needs from its owner.
protocol TravelStoreHost: AnyObject {
    /// See `AppModel.accountGeneration`. Work that awaits the network captures it before leaving
    /// and drops its answer if it has moved on.
    var accountGeneration: Int { get }
    var backendCoupleID: UUID? { get }
    var currentUser: Person { get }
    var partner: Person { get }
    var backend: any CoupleDataBackend { get }
    var writeRefusedMessage: String? { get set }
    /// Applies a write, queues it in the outbox and sends it — see `AppModel.commit`.
    func commit(_ write: PendingWrite, onRefusal: () -> Void) async
    /// Puts everything still in the outbox back on top of what a refresh just brought in.
    func reapplyPendingWrites()
    func checkReviewMilestones()
    /// Rewrites the widget snapshot, in the background.
    func refreshWidgets()
}

@Observable
final class TravelStore: AccountScopedStore {
    var trips: [Trip] = []
    var memories: [Memory] = []
    /// Every flight for the couple, independent of trip linkage — the authoritative list.
    /// See `Trip.flight` for the trip-scoped mirror kept for backward-compat UI.
    var flights: [Flight] = []
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
    private(set) var pendingTripIDs: Set<Trip.ID> = []
    private(set) var pendingMemoryIDs: Set<Memory.ID> = []
    /// A real AeroAPI-resolved flight picked while adding a trip pre-pairing — `addTrip`'s
    /// caller can't attach it via `AeroFlightService.addFlight` yet, since the trip it belongs
    /// to doesn't exist server-side until pairing completes. Kept here (not just as local
    /// `@State` on the view) so it survives past that screen and gets attempted once the trip
    /// is actually inserted, in `performAdopt(_:)` — previously this was silently dropped.
    private(set) var pendingFlightCandidates: [Trip.ID: (candidates: [AeroFlightCandidate], travelerIDs: [Person.ID])] = [:]
    /// A pending memory's photos can't be uploaded until there's a real couple to namespace the
    /// storage path under — held here so they aren't silently dropped, and uploaded once paired.
    private(set) var pendingMemoryPhotoData: [Memory.ID: [Data]] = [:]

    @ObservationIgnored weak var host: (any TravelStoreHost)?

    func reset() {
        pendingTripIDs = []
        pendingMemoryIDs = []
        pendingMemoryPhotoData = [:]
        pendingFlightCandidates = [:]
        trips = []
        memories = []
        flights = []
    }

    // MARK: - Through the host

    private var accountGeneration: Int { host?.accountGeneration ?? -1 }
    /// False once the host has gone, as well as once the account has.
    private func isCurrent(_ generation: Int) -> Bool { host != nil && generation == accountGeneration }
    private var backendCoupleID: UUID? { host?.backendCoupleID }
    private var currentUser: Person { host?.currentUser ?? Self.nobody }
    private var partner: Person { host?.partner ?? Self.nobody }
    private var backend: any CoupleDataBackend { host?.backend ?? LiveCoupleDataBackend() }
    private var writeRefusedMessage: String? {
        get { host?.writeRefusedMessage }
        set { host?.writeRefusedMessage = newValue }
    }
    private func commit(_ write: PendingWrite, onRefusal: () -> Void) async {
        await host?.commit(write, onRefusal: onRefusal)
    }
    private func reapplyPendingWrites() { host?.reapplyPendingWrites() }
    private func checkReviewMilestones() { host?.checkReviewMilestones() }
    private static let nobody = Person(name: "", accentColor: Person.palette[0])

    // MARK: - The outbox's travel writes

    /// The local half of a trip, flight or memory write: what the screen should show once it has
    /// landed. Every other write is the couple's own, and `AppModel` applies those.
    func apply(_ write: PendingWrite) {
        switch write {
        case .tripEdit(let edit):
            guard let index = trips.firstIndex(where: { $0.id == edit.tripID }) else { return }
            edit.apply(to: &trips[index])
        case .trip(let trip):
            guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
            var applied = trip
            applied.flights = trips[index].flights
            trips[index] = applied
        case let .tripNotes(tripID, notes):
            guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
            trips[index].notes = notes
        case let .flightTrip(flightID, tripID):
            guard let index = flights.firstIndex(where: { $0.id == flightID }) else { return }
            let previousTripID = flights[index].tripID
            flights[index].tripID = tripID
            if let previousTripID { syncTripFlights(tripID: previousTripID) }
            if let tripID { syncTripFlights(tripID: tripID) }
        case let .flightTravelers(flightID, travelerIDs):
            guard let index = flights.firstIndex(where: { $0.id == flightID }) else { return }
            flights[index].travelerIDs = travelerIDs
            if let tripID = flights[index].tripID { syncTripFlights(tripID: tripID) }
        case .memoryEdit(let edit):
            guard let index = memories.firstIndex(where: { $0.id == edit.memoryID }) else { return }
            edit.apply(to: &memories[index])
        case .memory(let memory):
            // The fields `updateMemory` writes, and only those: photos are added and removed by
            // writes of their own, and a copy's photo list may be older than the one on screen.
            guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
            memories[index].title = memory.title
            memories[index].place = memory.place
            memories[index].date = memory.date
            memories[index].note = memory.note
        case let .memoryTrip(memoryID, tripID):
            guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
            memories[index].tripID = tripID
        case let .memoryPhotos(memoryID, photos):
            guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
            let shown = Set(memories[index].photos.map(\.id))
            memories[index].photos.append(contentsOf: photos.filter { !shown.contains($0.id) })
        case let .removeMemoryPhoto(memoryID, photoID, _):
            guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
            memories[index].photos.removeAll { $0.id == photoID }
        case .firstName, .partnerNickname, .partnerHomeCity, .homeCity, .anniversaryDate:
            break
        }
    }

    /// A refresh's trips or memories, with anything not yet created kept. The server doesn't have
    /// those, so a plain overwrite dropped them from the screen — and `performAdopt`, which builds
    /// its retry list from what is on screen, then stopped retrying them.
    private func mergingPendingTrips(_ fresh: [Trip]) -> [Trip] {
        fresh.filter { !pendingTripIDs.contains($0.id) } + trips.filter { pendingTripIDs.contains($0.id) }
    }

    private func mergingPendingMemories(_ fresh: [Memory]) -> [Memory] {
        fresh.filter { !pendingMemoryIDs.contains($0.id) } + memories.filter { pendingMemoryIDs.contains($0.id) }
    }

    /// An edit to a trip or memory that is itself still waiting to be created can't land before
    /// it — the row isn't there, and an update to a missing row succeeds having changed nothing.
    /// It waits in the queue until `performAdopt` has created what it refers to.
    func isReadyToSend(_ write: PendingWrite) -> Bool {
        switch write {
        case .tripEdit(let edit): !pendingTripIDs.contains(edit.tripID)
        case .trip(let trip): !pendingTripIDs.contains(trip.id)
        case .tripNotes(let tripID, _): !pendingTripIDs.contains(tripID)
        case .flightTrip(_, let tripID): tripID.map { !pendingTripIDs.contains($0) } ?? true
        case .memoryEdit(let edit): !pendingMemoryIDs.contains(edit.memoryID)
        case .memory(let memory): !pendingMemoryIDs.contains(memory.id)
        case let .memoryTrip(memoryID, tripID):
            !pendingMemoryIDs.contains(memoryID) && (tripID.map { !pendingTripIDs.contains($0) } ?? true)
        case .memoryPhotos(let memoryID, _): !pendingMemoryIDs.contains(memoryID)
        case .removeMemoryPhoto(let memoryID, _, _): !pendingMemoryIDs.contains(memoryID)
        case .flightTravelers, .firstName, .partnerNickname, .partnerHomeCity, .homeCity, .anniversaryDate: true
        }
    }

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

    /// The soonest reunion still ahead: the one trip whose countdown tile is coral on Travel.
    var nextReunionTripID: Trip.ID? {
        upcomingTrips.first { $0.category == .reunion && $0.departureDate > .now }?.id
    }

    var nextReunionDaysToGo: Int {
        guard let trip = upcomingTrips.first else { return 0 }
        let days = TimeMath.daysUntil(trip.departureDate)
        return max(0, days)
    }

    func memories(in place: Place) -> [Memory] {
        memories.filter { $0.place?.isSameSpot(as: place) == true }
    }

    var citiesWithMemories: [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard let place = memory.place, !seen.contains(place.id) else { return nil }
            seen.insert(place.id)
            return place
        }
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
    func prefetchMemoryPhotos() {
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

    /// Restores memories that were added before pairing (or otherwise never synced) from local
    /// disk — see `PendingMemoryStore`. Runs before `adopt(_:)`/`adoptSoloProfile(_:)` so
    /// whichever one runs next already sees them: `adopt(_:)` will attempt to sync them
    /// immediately (they're now in `pendingMemoryIDs`), and `adoptSoloProfile(_:)` preserves
    /// pending memories through its reset rather than discarding them. Skips anything already
    /// present (e.g. a second call this session) to avoid duplicate entries.
    func restorePendingMemoriesFromDisk() {
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
    func restorePendingTripsFromDisk() {
        for trip in PendingTripStore.loadAll() {
            guard !trips.contains(where: { $0.id == trip.id }) else { continue }
            trips.append(trip)
            pendingTripIDs.insert(trip.id)
        }
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
    func startFlightsRealtimeSubscription(coupleID: UUID) async {
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

    func stopFlightsRealtimeSubscription() async {
        flightsRealtimeTask?.cancel()
        flightsRealtimeTask = nil
        if let flightsRealtimeChannel {
            await BackendService.unsubscribe(flightsRealtimeChannel)
        }
        flightsRealtimeChannel = nil
        flightsRealtimeCoupleID = nil
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
                try await backend.insertTrip(coupleID: backendCoupleID, trip: trip)
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
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard let backendCoupleID else { return }
        let generation = accountGeneration
        if let fresh = try? await BackendService.fetchFlights(coupleID: backendCoupleID) {
            // Not for an account that signed out meanwhile — it would start that couple's Live
            // Activities again for whoever holds the phone now.
            guard isCurrent(generation) else { return }
            flights = fresh
            for index in trips.indices {
                trips[index].flights = fresh.filter { $0.tripID == trips[index].id }
            }
            await resolveMissingAirportTimezones()
            guard isCurrent(generation) else { return }
            reapplyPendingWrites()
            // `flights`, not `fresh`: by now it carries the airport zones resolved above and any
            // pending edits, and those zones go onto a new card's attributes for life (FLT-5).
            await LiveActivityManager.shared.reconcileOnLaunch(with: flights)
            guard isCurrent(generation) else { return }
            await LiveActivityManager.shared.syncActivities(
                for: flights,
                homeTimeZone: currentUser.homeCity?.timeZone ?? .current,
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
            host?.refreshWidgets()
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
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
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
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard let backendCoupleID else { return }
        let generation = accountGeneration
        if let fresh = try? await backend.fetchMemories(coupleID: backendCoupleID), isCurrent(generation) {
            memories = mergingPendingMemories(fresh)
            reapplyPendingWrites()
        }
    }

    /// Re-pulls the full trip list from the backend — same purpose/gap as `refreshMemories()`
    /// above. Flight linkage is filled in from whatever's already in `flights` immediately (in
    /// case `refreshFlights()` isn't also called this cycle), then `refreshFlights()` — called
    /// alongside this everywhere it matters — re-links authoritatively from the fetched flight
    /// rows regardless of call order.
    func refreshTrips() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard let backendCoupleID else { return }
        let generation = accountGeneration
        if var fresh = try? await backend.fetchTrips(coupleID: backendCoupleID), isCurrent(generation) {
            for index in fresh.indices {
                fresh[index].flights = flights.filter { $0.tripID == fresh[index].id }
            }
            trips = mergingPendingTrips(fresh)
            reapplyPendingWrites()
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
        PendingWriteStore.removeAll(targeting: flight.id)
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

    /// Who is on this flight — `Flight.travellerIDs(linkedTrip:)` with its trip looked up. The one
    /// answer the Live Activity, the widget, the tracking screen, the map and the share sticker all
    /// use (FLT-14).
    func travellerIDs(for flight: Flight) -> [UUID] {
        flight.travellerIDs(linkedTrip: flight.tripID.flatMap { id in trips.first { $0.id == id } })
    }

    /// Whether the partner, not the viewer, is the one on the plane — from `travellerIDs(for:)`.
    /// Only decides *whose name* the Live Activity shows; deliberately separate from `isReunion`
    /// below, which the same check used to do double duty for. For a flight where both of them are
    /// travelling the viewer counts as travelling too.
    private func isPartnerTravelling(_ flight: Flight) -> Bool {
        let travellers = travellerIDs(for: flight)
        // Nobody recorded at all: most tracked flights are the partner's.
        guard !travellers.isEmpty else { return true }
        return !travellers.contains(currentUser.id)
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
        let originalNotes = trips[index].notes
        if pendingTripIDs.contains(trip.id) {
            // Not created yet: the edit goes into the copy that will be.
            trips[index].notes = trip.notes
            PendingTripStore.save(trips[index])
            return
        }
        await commit(.tripNotes(tripID: trip.id, notes: trip.notes)) {
            if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index].notes = originalNotes }
            writeRefusedMessage = Self.tripsRefusedMessage
        }
    }

    private static let tripsRefusedMessage = "Changes to your trips need an active subscription. Nothing was saved."

    /// Full edit of a trip's own fields (origin/destination/dates/category/notes) — as opposed
    /// to `updateTripNotes`, which only ever touched notes. Preserves the trip's linked flights
    /// (not part of what this edits).
    ///
    /// Sends only the fields that differ between `trip` and `base` — the copy the editor started
    /// from, or what is on screen now if there was none (`TripEdit`). The whole row used to go,
    /// so a partner's change to a field this edit never touched was undone by it (HOME-7).
    func updateTrip(_ trip: Trip, from base: Trip? = nil) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        let original = trips[index]
        var edit = TripEdit(from: base ?? original, to: trip)
        // Recomputed from the trip as it will be, since either city could have changed — and the
        // other one may be a partner's newer choice than the editor's copy knew.
        edit.distanceKm = nil
        var result = original
        edit.apply(to: &result)
        if edit.origin != nil || edit.destination != nil {
            edit.distanceKm = Geo.distanceKm(result.origin.coordinate, result.destination.coordinate)
        }
        guard !edit.isEmpty else { return }
        if pendingTripIDs.contains(trip.id) {
            // Not created yet, so there is no row to update — the edit used to be sent anyway, came
            // back as "no rows", and was rolled back as if refused. It goes into the copy that will
            // be created instead.
            apply(.tripEdit(edit))
            PendingTripStore.save(trips[index])
            return
        }
        // The same fields, back as they were before the edit — not the whole copy, which would
        // also undo anything a refresh brought in meanwhile. Taken before the edit rather than
        // refetched: this has to work with no network (a refusal can arrive while the connection
        // is fine and the subscription is not), and a refetch would be a second thing to fail
        // while undoing the first.
        let undo = TripEdit(from: result, to: original)
        await commit(.tripEdit(edit)) {
            apply(.tripEdit(undo))
            writeRefusedMessage = Self.tripsRefusedMessage
        }
    }

    func deleteTrip(_ trip: Trip) async {
        // Captured before the removal below so a failed delete can put both back exactly as
        // they were, rather than leaving the trip permanently gone from the UI while the row
        // still exists server-side.
        let affectedFlightIDs = Set(flights.filter { $0.tripID == trip.id }.map(\.id))
        trips.removeAll { $0.id == trip.id }
        pendingTripIDs.remove(trip.id)
        PendingTripStore.remove(id: trip.id)
        PendingWriteStore.removeAll(targeting: trip.id)
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
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        await setFlightTrip(flight, tripID: trip.id, previous: flights[index].tripID)
    }

    func unlinkFlight(_ flight: Flight) async {
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        await setFlightTrip(flight, tripID: nil, previous: flights[index].tripID)
    }

    private func setFlightTrip(_ flight: Flight, tripID: UUID?, previous: UUID?) async {
        await commit(.flightTrip(flightID: flight.id, tripID: tripID)) {
            apply(.flightTrip(flightID: flight.id, tripID: previous))
            writeRefusedMessage = Self.tripsRefusedMessage
        }
    }

    /// Same gap `linkFlight`/`unlinkFlight` closed for `tripID` — travelers were also only ever
    /// set once, at add-flight time, with no way to change them afterward. Pass an empty array
    /// to clear (e.g. neither partner is confirmed as the traveler yet); pass both ids when
    /// they're travelling together.
    func setFlightTravelers(_ flight: Flight, travelerIDs: [UUID]) async {
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        let previous = flights[index].travelerIDs
        await commit(.flightTravelers(flightID: flight.id, travelerIDs: travelerIDs)) {
            apply(.flightTravelers(flightID: flight.id, travelerIDs: previous))
            writeRefusedMessage = Self.tripsRefusedMessage
        }
    }

    /// Memories have no automatic trip association (no place/date matching) — linking is
    /// always this explicit, user-driven action from Trip Details.
    func linkMemory(_ memory: Memory, to trip: Trip) async {
        await setMemoryTrip(memory, tripID: trip.id)
    }

    func unlinkMemory(_ memory: Memory) async {
        await setMemoryTrip(memory, tripID: nil)
    }

    private func setMemoryTrip(_ memory: Memory, tripID: UUID?) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        let previous = memories[index].tripID
        await commit(.memoryTrip(memoryID: memory.id, tripID: tripID)) {
            apply(.memoryTrip(memoryID: memory.id, tripID: previous))
            writeRefusedMessage = Self.memoriesRefusedMessage
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
                photoPaths.append(try await backend.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
            }
            let photos = try await backend.insertMemory(coupleID: backendCoupleID, memory: memory, photoPaths: photoPaths)
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index].photos = photos
            }
            host?.refreshWidgets()
        } catch {
            if BackendService.isPermanentRefusal(error) {
                // It will never land, so keeping it as "pending" retried it on every adopt for as
                // long as the app was installed, while showing a memory that existed nowhere else.
                memories.removeAll { $0.id == memory.id }
                writeRefusedMessage = "Adding memories needs an active subscription. Nothing was saved."
                return memory
            }
            // To disk, as the solo branch above does, and swapped in with its photos pointing at
            // the local files. This used to be kept in memory only: the photos didn't show while it
            // waited, and if the app was killed before the next adopt sent it, it was gone.
            let persisted = PendingMemoryStore.save(memory: memory, photosData: imagesData)
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index] = persisted
            }
            pendingMemoryIDs.insert(memory.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[memory.id] = imagesData }
        }

        return memories.first { $0.id == memory.id } ?? memory
    }

    /// Edits an existing memory's fields in place, optionally appending new photos in the
    /// same call. Both go through the outbox, so made offline they show at once and are sent
    /// when the connection comes back.
    ///
    /// Only the fields that differ between `memory` and `base` are applied and sent — `base` being
    /// the copy the editor started from, or what is on screen now if there was none. The editor
    /// used to hand back its starting copy with the fields set, and all of it was written: its
    /// photo list over the one on screen (HOME-5), and every field to the server, over a partner's
    /// change to one this edit never touched (HOME-7).
    func updateMemory(_ memory: Memory, from base: Memory? = nil, newImagesData: [Data] = []) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        let edit = MemoryEdit(from: base ?? memories[index], to: memory)

        guard backendCoupleID != nil, !pendingMemoryIDs.contains(memory.id) else {
            // Still pending (never synced) — everything happens locally, same as the initial
            // add: new photos join the accumulated pending data and get re-persisted, so the
            // edit shows immediately and survives a relaunch. Without this, editing a pending
            // memory before a partner joins silently dropped any newly-added photos (the
            // synced-path branch below only uploads when a couple already exists) and never
            // updated the on-disk copy, so the *previous* version would come back after a kill.
            var accumulatedPhotoData = pendingMemoryPhotoData[memory.id] ?? []
            accumulatedPhotoData.append(contentsOf: newImagesData)
            // Onto the copy on screen, whose photos are current: a photo removed while the editor
            // was open is already gone from it.
            var updated = memories[index]
            edit.apply(to: &updated)
            let persisted = PendingMemoryStore.save(memory: updated, photosData: accumulatedPhotoData)
            memories[index] = persisted
            pendingMemoryPhotoData[memory.id] = accumulatedPhotoData.isEmpty ? nil : accumulatedPhotoData
            return
        }

        // Everything below finds the memory again by id rather than holding on to `index`: each
        // `commit` awaits the network, and a refresh landing meanwhile can replace or reorder the
        // array — writing through the old index put photos on, or rolled back, a different memory.
        // Adding photos passes the memory back unchanged, so the edit is empty and nothing but
        // the photos is sent.
        if !edit.isEmpty {
            var result = memories[index]
            edit.apply(to: &result)
            let undo = MemoryEdit(from: result, to: memories[index])
            await commit(.memoryEdit(edit)) {
                apply(.memoryEdit(undo))
                writeRefusedMessage = Self.memoriesRefusedMessage
            }
        }

        guard !newImagesData.isEmpty else { return }
        // Written to disk first and shown from there, so picking photos offline no longer looks
        // like nothing happened, and they are uploaded with the rest of the outbox.
        let standIns = newImagesData.compactMap(PendingWriteStore.savePhoto)
        guard !standIns.isEmpty else { return }
        await commit(.memoryPhotos(memoryID: memory.id, photos: standIns)) {
            let ids = Set(standIns.map(\.id))
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index].photos.removeAll { ids.contains($0.id) }
            }
            writeRefusedMessage = "Adding photos needs an active subscription. Nothing was saved."
        }
    }

    private static let memoriesRefusedMessage = "Changes to your memories need an active subscription. Nothing was saved."

    func removePhoto(_ photo: MemoryPhoto, from memory: Memory) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        let position = memories[index].photos.firstIndex { $0.id == photo.id }
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

        // Added offline and not uploaded yet: there is nothing on the server to remove.
        guard !photo.isPending else {
            PendingWriteStore.removeQueuedPhoto(id: photo.id)
            return
        }

        await commit(.removeMemoryPhoto(memoryID: memory.id, photoID: photo.id, path: photo.path)) {
            // This used to keep the removal on screen whatever happened.
            if let index = memories.firstIndex(where: { $0.id == memory.id }),
               !memories[index].photos.contains(where: { $0.id == photo.id }) {
                memories[index].photos.insert(photo, at: min(position ?? 0, memories[index].photos.count))
            }
            writeRefusedMessage = Self.memoriesRefusedMessage
        }
    }

    func deleteMemory(_ memory: Memory) async {
        memories.removeAll { $0.id == memory.id }
        pendingMemoryIDs.remove(memory.id)
        pendingMemoryPhotoData.removeValue(forKey: memory.id)
        PendingMemoryStore.remove(id: memory.id)
        PendingWriteStore.removeAll(targeting: memory.id)
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

    /// Creates the trips and memories drafted before there was a couple — onboarding's first trip,
    /// or Home's add cards while still solo — now that `couple` exists, and attaches any flight
    /// picked alongside one. What fails stays pending, for the next adopt to try again. False when
    /// the account changed partway, and the caller should stop.
    func flushLocalOnly(trips localOnlyTrips: [Trip], memories localOnlyMemories: [Memory], into couple: Couple, startedIn generation: Int) async -> Bool {
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
                (id == couple.partnerA.id || id == couple.partnerB.id) ? id : couple.partnerB.id
            }
            do {
                try await backend.insertTrip(coupleID: couple.id, trip: tripToInsert)
                guard isCurrent(generation) else { return false }
                // Now durably on the backend — the local disk copy was only ever a stand-in
                // until this succeeded.
                PendingTripStore.remove(id: trip.id)
            } catch {
                guard isCurrent(generation) else { return false }
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
                let added = (try? await AeroFlightService.addFlight(candidate: candidate, tripID: tripID, travelerIDs: pending.travelerIDs, notifyMe: true)) != nil
                guard isCurrent(generation) else { return false }
                if added {
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
            guard isCurrent(generation) else { return false }
        }

        var stillPendingMemories = Set<Memory.ID>()
        for memory in localOnlyMemories {
            var synced = memory
            do {
                var photoPaths: [String] = []
                for imageData in pendingMemoryPhotoData[memory.id] ?? [] {
                    photoPaths.append(try await backend.uploadMemoryPhoto(coupleID: couple.id, memoryID: memory.id, imageData: imageData))
                }
                synced.photos = try await backend.insertMemory(coupleID: couple.id, memory: memory, photoPaths: photoPaths)
                guard isCurrent(generation) else { return false }
                pendingMemoryPhotoData.removeValue(forKey: memory.id)
                // Now durably on the backend — the local disk copy (and its cached photo
                // files) was only ever a stand-in until this succeeded.
                PendingMemoryStore.remove(id: memory.id)
            } catch {
                guard isCurrent(generation) else { return false }
                stillPendingMemories.insert(memory.id)
            }
            memories.append(synced)
        }
        pendingMemoryIDs = stillPendingMemories
        return true
    }
}
