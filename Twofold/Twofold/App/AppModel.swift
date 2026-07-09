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
    var couple: Couple = Couple(
        partnerA: Person(name: "You", accentColor: Person.palette[1]),
        partnerB: Person(name: "Partner", accentColor: Person.palette[0]),
        startedDatingOn: .now
    )
    var trips: [Trip] = []
    var memories: [Memory] = []

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
    /// A pending memory's photo can't be uploaded until there's a real couple to namespace the
    /// storage path under — held here so it isn't silently dropped, and uploaded once paired.
    private var pendingMemoryPhotoData: [Memory.ID: Data] = [:]

    var currentUser: Person { couple.partnerA }
    var partner: Person { couple.partnerB }

    var needsPartnerInvite: Bool { !partnerConnected }
    var needsFirstTrip: Bool { trips.isEmpty }
    var needsFirstFlight: Bool { !trips.contains { $0.flight != nil } }
    var needsHomeCities: Bool { couple.partnerA.homeCity == nil || couple.partnerB.homeCity == nil }

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming || $0.isActive }.sorted { $0.departureDate < $1.departureDate }
    }

    var pastTrips: [Trip] {
        trips.filter { !$0.isUpcoming && !$0.isActive }.sorted { $0.departureDate > $1.departureDate }
    }

    var stats: MockData.RelationshipStats {
        let totalDistance = trips.reduce(0) { $0 + $1.distanceKm }
        return MockData.RelationshipStats(
            totalDistanceKm: totalDistance,
            tripCount: trips.count,
            flightCount: trips.filter { $0.flight != nil }.count,
            countryCount: Set(trips.flatMap { [$0.origin.country, $0.destination.country] }).count,
            daysTogether: 0,
            earthMultiple: totalDistance / Geo.earthCircumferenceKm
        )
    }

    var nextReunionDaysToGo: Int {
        guard let trip = upcomingTrips.first else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    func memories(in place: Place) -> [Memory] {
        memories.filter { $0.place.id == place.id }
    }

    var citiesWithMemories: [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard !seen.contains(memory.place.id) else { return nil }
            seen.insert(memory.place.id)
            return memory.place
        }
    }

    // MARK: - Session / backend sync

    /// Called once at launch. Restores a session if one exists and loads real couple/trip
    /// state; leaves `hasCouple = false` so `RootView` routes into onboarding if there's no
    /// session, or the session hasn't finished pairing yet.
    func restoreSession() async {
        defer { isLoadingSession = false }
        guard await BackendService.restoreSession() != nil else { return }
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
        }
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
        partnerConnected = true
        hasCouple = true

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
                var photoPath: String?
                if let imageData = pendingMemoryPhotoData[memory.id] {
                    photoPath = try await BackendService.uploadMemoryPhoto(coupleID: state.couple.id, memoryID: memory.id, imageData: imageData)
                }
                try await BackendService.insertMemory(coupleID: state.couple.id, memory: memory, photoPath: photoPath)
                if let photoPath {
                    synced.photoURL = try? await BackendService.memoryPhotoSignedURL(path: photoPath)
                }
                pendingMemoryPhotoData.removeValue(forKey: memory.id)
            } catch {
                stillPendingMemories.insert(memory.id)
            }
            memories.append(synced)
        }
        pendingMemoryIDs = stillPendingMemories
    }

    /// Called once account creation succeeds — the single place everything collected during
    /// the default onboarding flow (situation/frequency/attribution/goals stay local to
    /// `OnboardingModel` for analytics-style use later; names/cities/drafted flight apply
    /// here) gets persisted, since nothing could be written to Supabase before a session
    /// existed. If a real couple already exists (the partner redeemed an invite in a race,
    /// or this is the preserved deep-link path resuming), adopts it; otherwise the partner
    /// stays a personalized local placeholder until real pairing happens later.
    func completeOnboarding(_ onboarding: OnboardingModel) async {
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
            couple.partnerB.name = onboarding.partnerName
        }
        if let partnerCity = onboarding.partnerCity {
            couple.partnerB.homeCity = partnerCity
        }

        inviteCode = onboarding.inviteCode
        hasCouple = true
    }

    @discardableResult
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, flightNumber: String?) async -> Trip {
        let travelerID = traveler == .partner ? partner.id : currentUser.id
        let category: TripCategory = traveler == .both ? .together : .seeingEachOther
        let distance = Geo.distanceKm(origin.coordinate, destination.coordinate)

        var trip = Trip(
            travelerID: travelerID,
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            category: category,
            distanceKm: distance
        )

        if let flightNumber, !flightNumber.isEmpty {
            trip.flight = Flight(
                flightNumber: flightNumber,
                origin: origin,
                destination: destination,
                status: .scheduled,
                scheduledDeparture: departureDate,
                scheduledArrival: arrivalDate,
                progress: 0,
                timeline: []
            )
        }

        trips.append(trip)

        if let backendCoupleID {
            do {
                try await BackendService.insertTrip(coupleID: backendCoupleID, trip: trip)
            } catch {
                pendingTripIDs.insert(trip.id)
            }
        } else {
            pendingTripIDs.insert(trip.id)
        }

        return trip
    }

    func addFlight(to tripID: Trip.ID, flightNumber: String) async {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let trip = trips[index]
        let flight = Flight(
            flightNumber: flightNumber,
            origin: trip.origin,
            destination: trip.destination,
            status: .scheduled,
            scheduledDeparture: trip.departureDate,
            scheduledArrival: trip.arrivalDate,
            progress: 0,
            timeline: []
        )
        trips[index].flight = flight

        guard !pendingTripIDs.contains(tripID) else { return }
        try? await BackendService.insertFlight(tripID: tripID, flight: flight)
    }

    @discardableResult
    func addMemory(title: String, place: Place, date: Date, emoji: String, note: String, imageData: Data?) async -> Memory {
        var memory = Memory(title: title, emoji: emoji, place: place, date: date, note: note)
        memories.append(memory)

        guard let backendCoupleID else {
            pendingMemoryIDs.insert(memory.id)
            if let imageData { pendingMemoryPhotoData[memory.id] = imageData }
            return memory
        }

        do {
            var photoPath: String?
            if let imageData {
                photoPath = try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData)
            }
            try await BackendService.insertMemory(coupleID: backendCoupleID, memory: memory, photoPath: photoPath)
            if let photoPath, let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memory.photoURL = try? await BackendService.memoryPhotoSignedURL(path: photoPath)
                memories[index].photoURL = memory.photoURL
            }
        } catch {
            pendingMemoryIDs.insert(memory.id)
            if let imageData { pendingMemoryPhotoData[memory.id] = imageData }
        }

        return memory
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
