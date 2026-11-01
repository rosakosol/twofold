//
//  CoupleDataBackend.swift
//  Twofold
//
//  The backend calls AppModel makes for trips, memories, flight links and profile fields, behind
//  a protocol so a unit test can stand in for the network. `LiveCoupleDataBackend` forwards each
//  one to `BackendService` unchanged; nothing else implements it outside the tests.
//
//  Deliberately narrow: only what AppModel's own write and refresh paths call. Feature views keep
//  calling `BackendService` directly, and the couple-state fetch behind `adopt` is not here.
//

import Foundation

protocol CoupleDataBackend {
    func fetchTrips(coupleID: UUID) async throws -> [Trip]
    func fetchMemories(coupleID: UUID) async throws -> [Memory]

    func insertTrip(coupleID: UUID, trip: Trip) async throws
    func updateTrip(_ edit: TripEdit) async throws
    func updateTripNotes(tripID: UUID, notes: String?) async throws
    func setFlightTrip(flightID: UUID, tripID: UUID?) async throws
    func setFlightTravelers(flightID: UUID, travelerIDs: [UUID]) async throws

    func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String
    func insertMemory(coupleID: UUID, memory: Memory, photoPaths: [String]) async throws -> [MemoryPhoto]
    func updateMemory(_ edit: MemoryEdit) async throws
    func addMemoryPhotos(memoryID: UUID, photoPaths: [String], startingPosition: Int) async throws -> [MemoryPhoto]
    func deleteMemoryPhoto(id: UUID, path: String) async throws
    func setMemoryTrip(memoryID: UUID, tripID: UUID?) async throws

    func updateFirstName(_ name: String) async throws
    func updatePartnerNickname(_ name: String) async throws
    func updatePartnerHomeCityGuess(_ place: Place) async throws
    func updateHomeCity(_ place: Place) async throws
    func updateAnniversaryDate(_ date: Date) async throws
    func updateCoupleAnniversaryDate(coupleID: UUID, date: Date) async throws
}

struct LiveCoupleDataBackend: CoupleDataBackend {
    /// The end-to-end tests' stand-in for a connection that drops writes (`TWOFOLD_E2E_WRITES_FAIL`,
    /// DEBUG only — always false in a release build).
    private func failIfWritesAreDown() throws {
        if E2ELaunch.writesFail { throw URLError(.notConnectedToInternet) }
    }

    func fetchTrips(coupleID: UUID) async throws -> [Trip] {
        try await BackendService.fetchTrips(coupleID: coupleID)
    }

    func fetchMemories(coupleID: UUID) async throws -> [Memory] {
        try await BackendService.fetchMemories(coupleID: coupleID)
    }

    func insertTrip(coupleID: UUID, trip: Trip) async throws {
        try failIfWritesAreDown()
        try await BackendService.insertTrip(coupleID: coupleID, trip: trip)
    }

    func updateTrip(_ edit: TripEdit) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateTrip(edit)
    }

    func updateTripNotes(tripID: UUID, notes: String?) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateTripNotes(tripID: tripID, notes: notes)
    }

    func setFlightTrip(flightID: UUID, tripID: UUID?) async throws {
        try failIfWritesAreDown()
        try await BackendService.setFlightTrip(flightID: flightID, tripID: tripID)
    }

    func setFlightTravelers(flightID: UUID, travelerIDs: [UUID]) async throws {
        try failIfWritesAreDown()
        try await BackendService.setFlightTravelers(flightID: flightID, travelerIDs: travelerIDs)
    }

    func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String {
        try failIfWritesAreDown()
        return try await BackendService.uploadMemoryPhoto(coupleID: coupleID, memoryID: memoryID, imageData: imageData)
    }

    func insertMemory(coupleID: UUID, memory: Memory, photoPaths: [String]) async throws -> [MemoryPhoto] {
        try failIfWritesAreDown()
        return try await BackendService.insertMemory(coupleID: coupleID, memory: memory, photoPaths: photoPaths)
    }

    func updateMemory(_ edit: MemoryEdit) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateMemory(edit)
    }

    func addMemoryPhotos(memoryID: UUID, photoPaths: [String], startingPosition: Int) async throws -> [MemoryPhoto] {
        try failIfWritesAreDown()
        return try await BackendService.addMemoryPhotos(memoryID: memoryID, photoPaths: photoPaths, startingPosition: startingPosition)
    }

    func deleteMemoryPhoto(id: UUID, path: String) async throws {
        try failIfWritesAreDown()
        try await BackendService.deleteMemoryPhoto(id: id, path: path)
    }

    func setMemoryTrip(memoryID: UUID, tripID: UUID?) async throws {
        try failIfWritesAreDown()
        try await BackendService.setMemoryTrip(memoryID: memoryID, tripID: tripID)
    }

    func updateFirstName(_ name: String) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateFirstName(name)
    }

    func updatePartnerNickname(_ name: String) async throws {
        try failIfWritesAreDown()
        try await BackendService.updatePartnerNickname(name)
    }

    func updatePartnerHomeCityGuess(_ place: Place) async throws {
        try failIfWritesAreDown()
        try await BackendService.updatePartnerHomeCityGuess(place)
    }

    func updateHomeCity(_ place: Place) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateHomeCity(place)
    }

    func updateAnniversaryDate(_ date: Date) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateAnniversaryDate(date)
    }

    func updateCoupleAnniversaryDate(coupleID: UUID, date: Date) async throws {
        try failIfWritesAreDown()
        try await BackendService.updateCoupleAnniversaryDate(coupleID: coupleID, date: date)
    }
}
