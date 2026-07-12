//
//  AppModel.swift
//  Twofold
//
//  Root store backed by Supabase. `couple`/`trips`/`memories` are loaded from the backend
//  once a session exists.
//

import Foundation
import Observation

@Observable
final class AppModel {
    var isLoadingSession = true
    var hasCouple: Bool = false
    var couple: Couple = AppModel.placeholderCouple
    var trips: [Trip] = []
    var memories: [Memory] = []
    /// Every flight for the couple, independent of trip linkage — the authoritative list.
    /// See `Trip.flight` for the trip-scoped mirror kept for backward-compat UI.
    var flights: [Flight] = []
    /// Home-screen doodle pads — only meaningful once paired, since there's no partner pad to
    /// compare against (and nowhere real to save to) before then.
    var myDrawingURL: URL?
    var partnerDrawingURL: URL?

    /// "Your partner doesn't pay anything" — true if *either* partner's device last reported
    /// an active local StoreKit entitlement (see `BackendService.fetchSubscriptionActive`).
    /// `RootView` gates all of `MainTabView` behind this once `hasCouple` is true.
    var isSubscriptionActive = false

    /// Whether the partner has actually redeemed an invite and joined — confirmed by the
    /// backend (an active `couples` row exists), not assumed the moment a code is shared.
    var partnerConnected: Bool = false
    var inviteCode: String?

    /// Set once a real `couples` row exists for this user.
    private var backendCoupleID: UUID?
    /// Trips/memories added locally before pairing completed (no couple to attach them to
    /// yet). Flushed to the backend the moment a real couple shows up.
    private var pendingTripIDs: Set<Trip.ID> = []
    private var pendingMemoryIDs: Set<Memory.ID> = []
    /// A pending memory's photos can't be uploaded until there's a real couple to namespace the
    /// storage path under — held here so they aren't silently dropped, and uploaded once paired.
    private var pendingMemoryPhotoData: [Memory.ID: [Data]] = [:]

    var currentUser: Person { couple.partnerA }
    var partner: Person { couple.partnerB }

    var needsPartnerInvite: Bool { !partnerConnected }
    var needsFirstTrip: Bool { trips.isEmpty }
    var needsFirstFlight: Bool { !trips.contains { $0.flight != nil } }
    var needsHomeCities: Bool { couple.partnerA.homeCity == nil || couple.partnerB.homeCity == nil }

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    /// The couple's relevant tracked flights for the Home carousel — whichever are currently in
    /// progress or haven't departed yet, soonest departure first. Cancelled flights are excluded
    /// (nothing useful to show live for those).
    var activeOrUpcomingFlights: [Flight] {
        let relevant = flights.filter { !$0.cancelled && ($0.status.isActivelyTracked || ($0.bestArrival ?? .distantPast) > .now) }
        return relevant.sorted { ($0.bestDeparture ?? .distantFuture) < ($1.bestDeparture ?? .distantFuture) }
    }

    /// Convenience for call sites that only ever cared about the single most relevant flight.
    var activeOrUpcomingFlight: Flight? { activeOrUpcomingFlights.first }

    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming || $0.isActive }.sorted { $0.departureDate < $1.departureDate }
    }

    var pastTrips: [Trip] {
        trips.filter { !$0.isUpcoming && !$0.isActive }.sorted { $0.departureDate > $1.departureDate }
    }

    var stats: MockData.RelationshipStats {
        let totalDistance = trips.reduce(0) { $0 + $1.distanceKm }
        let daysTogether = max(0, Calendar.current.dateComponents([.day], from: couple.startedDatingOn, to: .now).day ?? 0)
        return MockData.RelationshipStats(
            totalDistanceKm: totalDistance,
            tripCount: trips.count,
            flightCount: trips.filter { $0.flight != nil }.count,
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
        guard await BackendService.restoreSession() != nil else { return }
        await loadSignedInState()
    }

    /// Called any time we know a Supabase session exists — at launch (`restoreSession`), right
    /// after a manual sign-in (`SignInView`), or after `removePartner()` dissolves a couple.
    /// Being authenticated at all means onboarding is already done, regardless of whether a
    /// `couples` row exists yet — so this always ends with `hasCouple = true`, rather than
    /// leaving a solo (unpaired) user to fall back into onboarding just because
    /// `fetchCoupleState` found nothing.
    func loadSignedInState() async {
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
        } else if let profile = try? await BackendService.fetchOwnProfile() {
            // Reset everything to a clean slate first — at launch these are already at their
            // zero-value defaults so this is a no-op, but this branch is also reached after
            // `removePartner()` dissolves a couple on an AppModel that still has the *old*
            // partner's data loaded (partnerConnected, backendCoupleID, trips/memories/flights,
            // drawing pad URLs). Without this, all of that stale state survives — which is
            // exactly what made a just-dissolved couple still look "connected" in the UI, and
            // made a second removal attempt fail (retrying against an already-dissolved couple).
            partnerConnected = false
            backendCoupleID = nil
            trips = []
            memories = []
            flights = []
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
        }
        hasCouple = true
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }

    /// A device's own successful purchase/restore, applied instantly and locally (no network
    /// round-trip) — `PaywallView` calls this right after a purchase/restore succeeds, before
    /// its own `onSubscribed()` callback fires, so `RootView`'s gate never flashes a second
    /// paywall for someone who just subscribed (the Supabase write happens alongside this, but
    /// this local flag is what `RootView` actually reads).
    func markSubscriptionActive() {
        isSubscriptionActive = true
    }

    /// Signs out and resets all local state back to the pre-auth placeholder — `RootView`
    /// picks this up via `hasCouple` and routes back to `WelcomeView`.
    func signOut() async {
        try? await BackendService.signOut()
        hasCouple = false
        partnerConnected = false
        inviteCode = nil
        backendCoupleID = nil
        isSubscriptionActive = false
        pendingTripIDs = []
        pendingMemoryIDs = []
        pendingMemoryPhotoData = [:]
        trips = []
        memories = []
        flights = []
        couple = Self.placeholderCouple
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
    func updateProfile(name: String, homeCity: Place?) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != couple.partnerA.name {
            try? await BackendService.updateFirstName(trimmedName)
            couple.partnerA.name = trimmedName
        }
        if let homeCity, homeCity.id != couple.partnerA.homeCity?.id {
            try? await BackendService.updateHomeCity(homeCity)
            couple.partnerA.homeCity = homeCity
        }
    }

    func updateAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadAvatar(imageData: imageData)
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
        couple.partnerB.avatarURL = url
    }

    func updateAnniversaryDate(_ date: Date) async {
        guard date != couple.startedDatingOn else { return }
        try? await BackendService.updateAnniversaryDate(date)
        couple.startedDatingOn = date
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
        await loadSignedInState()
        // HomeView's setup checklist card (the "invite your partner" hint) remembers a past
        // dismissal forever via this UserDefaults key — without clearing it, someone who'd
        // already dismissed it once (e.g. during their original onboarding) would see no hint
        // at all here, even though they're now genuinely back in the same unpaired state a
        // brand-new user starts in and need that same nudge again.
        UserDefaults.standard.set(false, forKey: "setupChecklistDismissed")
        return nil
    }

    /// Re-checks backend couple state without touching `isLoadingSession` — picks up a
    /// partner's invite redemption that happened while this device was backgrounded, the
    /// same idea as `GlobeHomeView`'s existing pending-share foreground refresh.
    func refreshCoupleStateIfNeeded() async {
        guard hasCouple, !partnerConnected else { return }
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
        }
    }

    /// Drawing pad paths are fully deterministic (`{coupleID}/{personID}/pad.png`), so unlike
    /// trips/memories there's nothing to "fetch" beyond just pointing at the URL — this just
    /// primes both URLs so the pad previews have something to render on first appearance.
    func loadDrawingPads() {
        guard let backendCoupleID else { return }
        myDrawingURL = BackendService.drawingPadPublicURL(coupleID: backendCoupleID, personID: currentUser.id)
        partnerDrawingURL = BackendService.drawingPadPublicURL(coupleID: backendCoupleID, personID: partner.id)
    }

    /// Only available once paired — there's no couple to namespace the storage path under
    /// beforehand, and no partner pad to make the feature meaningful yet.
    func saveMyDrawing(imageData: Data) async {
        guard let backendCoupleID else { return }
        let uploadedURL = try? await BackendService.uploadDrawingPad(coupleID: backendCoupleID, personID: currentUser.id, imageData: imageData)
        myDrawingURL = uploadedURL
        if uploadedURL != nil {
            Task { await BackendService.notifyPartner(event: .drawingSaved) }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        }
    }

    /// Adopts real couple/trip/memory rows from the backend, flushing anything that was added
    /// locally before pairing completed (drafted during onboarding, or via the home screen's
    /// "add a trip"/"add a memory" cards while still solo).
    private func adopt(_ state: BackendService.CoupleState) async {
        let localOnlyTrips = trips.filter { pendingTripIDs.contains($0.id) }
        let localOnlyMemories = memories.filter { pendingMemoryIDs.contains($0.id) }

        couple = state.couple
        backendCoupleID = state.couple.id
        trips = state.trips
        memories = state.memories
        flights = state.flights
        partnerConnected = true
        hasCouple = true
        isSubscriptionActive = state.subscriptionActive

        var stillPendingTrips = Set<Trip.ID>()
        for trip in localOnlyTrips {
            // Trips drafted before pairing (e.g. onboarding's "add first flight") were built
            // against a placeholder partner id that never existed as a real profile — remap
            // to the now-real partner so the FK on `trips.traveler_id` doesn't reject it.
            var tripToInsert = trip
            if tripToInsert.travelerID != state.couple.partnerA.id && tripToInsert.travelerID != state.couple.partnerB.id {
                tripToInsert.travelerID = state.couple.partnerB.id
            }
            do {
                try await BackendService.insertTrip(coupleID: state.couple.id, trip: tripToInsert)
            } catch {
                stillPendingTrips.insert(trip.id)
            }
            trips.append(tripToInsert)
        }
        pendingTripIDs = stillPendingTrips

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
            } catch {
                stillPendingMemories.insert(memory.id)
            }
            memories.append(synced)
        }
        pendingMemoryIDs = stillPendingMemories
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }

    /// Called once account creation succeeds — now happens *before* the paywall/trial screens
    /// rather than after, so a real account exists to tie the subscription to. Persists
    /// everything collected during the default onboarding flow (situation/frequency/
    /// attribution/goals stay local to `OnboardingModel` for analytics-style use later; names/
    /// cities/photos/drafted flight apply here) — nothing could be written to Supabase before
    /// a session existed. Deliberately does **not** set `hasCouple = true`: `RootView` swaps
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
        }

        if let selfPhotoData = onboarding.selfPhotoData,
           let url = try? await BackendService.uploadAvatar(imageData: selfPhotoData) {
            couple.partnerA.avatarURL = url
        }
        if let partnerPhotoData = onboarding.partnerPhotoData,
           let url = try? await BackendService.uploadPartnerAvatar(imageData: partnerPhotoData) {
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
    /// AeroAPI-resolved `AeroFlightCandidate` in hand should follow up with
    /// `AeroFlightService.addFlight(faFlightId:tripID:notifyMe:)` once this trip exists,
    /// exactly as `AddFirstFlightView`/`AddTripDetailsView` already do.
    @discardableResult
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, category: TripCategory) async -> Trip {
        let travelerID = traveler == .partner ? partner.id : currentUser.id
        let distance = Geo.distanceKm(origin.coordinate, destination.coordinate)

        let trip = Trip(
            travelerID: travelerID,
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            category: category,
            distanceKm: distance
        )

        trips.append(trip)

        if let backendCoupleID {
            do {
                try await BackendService.insertTrip(coupleID: backendCoupleID, trip: trip)
                Task { await BackendService.notifyPartner(event: .tripAdded, detail: "\(origin.city) to \(destination.city)") }
            } catch {
                pendingTripIDs.insert(trip.id)
            }
        } else {
            pendingTripIDs.insert(trip.id)
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
                trips[index].flight = fresh.first { $0.tripID == trips[index].id }
            }
            await LiveActivityManager.shared.reconcileOnLaunch(with: fresh)
            await LiveActivityManager.shared.syncActivities(
                for: fresh,
                travelerName: { [weak self] flight in
                    guard let self else { return "" }
                    return isReunion(flight) ? partner.name : currentUser.name
                },
                isReunion: isReunion
            )
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        }
    }

    /// Stops tracking a flight entirely (swipe-to-remove on the Trips tab). Re-runs
    /// `refreshFlights()` afterward rather than just filtering `flights` locally so the Live
    /// Activity sync/reconcile logic there — which already ends an Activity for any flight that
    /// disappeared from the fetched list — handles cleanup without duplicating that logic here.
    func deleteFlight(_ flight: Flight) async {
        try? await BackendService.deleteFlight(id: flight.id)
        await refreshFlights()
    }

    /// "Reunion" framing (the app's existing romantic language for "your partner is on their
    /// way to you") applies whenever the signed-in user isn't the one who added/is tracking
    /// this flight — defaults to true when `createdBy` is unset (e.g. an older row) since most
    /// tracked flights are the partner's.
    private func isReunion(_ flight: Flight) -> Bool {
        guard let createdBy = flight.createdBy else { return true }
        return createdBy != currentUser.id
    }

    /// Freeform trip prep notes — reused by the Flight Detail screen's "Trip checklist" card
    /// rather than inventing a separate checklist feature/table.
    func updateTripNotes(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index].notes = trip.notes
        try? await BackendService.updateTripNotes(tripID: trip.id, notes: trip.notes)
    }

    /// Registers this device's APNs token against the signed-in profile so
    /// `send-flight-notification` (server-side) has somewhere to deliver to. Safe to call
    /// repeatedly — the backend upserts on the token itself.
    func registerPushToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await BackendService.registerDeviceToken(token, environment: environment)
    }

    @discardableResult
    func addMemory(title: String, place: Place?, date: Date, note: String, imagesData: [Data]) async -> Memory {
        let memory = Memory(title: title, place: place, date: date, note: note)
        memories.append(memory)

        guard let backendCoupleID else {
            pendingMemoryIDs.insert(memory.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[memory.id] = imagesData }
            return memory
        }

        do {
            var photoPaths: [String] = []
            for imageData in imagesData {
                photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
            }
            let photos = try await BackendService.insertMemory(coupleID: backendCoupleID, memory: memory, photoPaths: photoPaths)
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index].photos = photos
            }
            Task { await BackendService.notifyPartner(event: .memoryAdded, detail: title) }
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
        memories[index] = memory

        do {
            try await BackendService.updateMemory(memory)
            if !newImagesData.isEmpty, let backendCoupleID {
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
        try? await BackendService.deleteMemoryPhoto(id: photo.id, path: photo.path)
    }

    func deleteMemory(_ memory: Memory) async {
        memories.removeAll { $0.id == memory.id }
        pendingMemoryIDs.remove(memory.id)
        pendingMemoryPhotoData.removeValue(forKey: memory.id)
        guard backendCoupleID != nil else { return }
        try? await BackendService.deleteMemory(id: memory.id, photoPaths: memory.photos.map(\.path))
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
