//
//  OfflineOutboxTests.swift
//  TwofoldTests
//
//  Writes made while the backend can't be reached (CORE-2, CORE-3, HOME-1, HOME-2, 5-home-NEW-2,
//  1-core-NEW-1, 1-core-NEW-2).
//
//  Each of these used to be applied on screen and then lost: a memory added while paired was kept
//  in memory only, the next refresh replaced the array with the server's copy and took pending
//  items and edits with it, and nothing ever sent an edit a second time. Driven through the real
//  AppModel with `CoupleDataBackend` replaced, so "offline" is a backend that throws a URLError.
//
//  Nested under `PendingMemoryDiskTests` because these write to `PendingMemoryStore` and
//  `PendingTripStore`, which the suites there also clear.
//

import Foundation
import Testing
@testable import Twofold

/// Throws a transport error for every write while `isOffline`, a refusal while `isRefusing`, and
/// otherwise records what it was asked to do. Fetches answer with `serverTrips`/`serverMemories`.
final class FakeCoupleDataBackend: CoupleDataBackend {
    var isOffline = false
    var isRefusing = false
    var serverTrips: [Trip] = []
    var serverMemories: [Memory] = []
    /// Runs inside `updateMemory`, between the call and its return — where a refresh can land.
    var duringUpdateMemory: (() -> Void)?
    /// Awaited inside `updateFirstName` before it lands, so a test can hold a send in the air.
    var beforeUpdateFirstName: (() async -> Void)?

    private(set) var calls: [String] = []
    /// Each edit as it arrived — only the fields it changed.
    private(set) var updatedMemories: [MemoryEdit] = []
    private(set) var updatedTrips: [TripEdit] = []
    private(set) var memoryTripLinks: [(memoryID: UUID, tripID: UUID?)] = []
    private(set) var firstNames: [String] = []
    private(set) var homeCities: [Place] = []
    private(set) var insertedMemories: [UUID] = []
    private(set) var insertedTrips: [UUID] = []
    private(set) var uploadedPhotoCount = 0

    private func write(_ name: String) throws {
        if isOffline { throw URLError(.notConnectedToInternet) }
        if isRefusing { throw BackendService.WriteAffectedNoRows() }
        calls.append(name)
    }

    func fetchTrips(coupleID: UUID) async throws -> [Trip] { serverTrips }
    func fetchMemories(coupleID: UUID) async throws -> [Memory] { serverMemories }

    func insertTrip(coupleID: UUID, trip: Trip) async throws {
        try write("insertTrip")
        insertedTrips.append(trip.id)
    }
    /// Writes the fields the app sends to the server's copy and leaves the rest, as PostgREST does.
    func updateTrip(_ edit: TripEdit) async throws {
        try write("updateTrip")
        updatedTrips.append(edit)
        if let index = serverTrips.firstIndex(where: { $0.id == edit.tripID }) {
            edit.apply(to: &serverTrips[index])
        }
    }
    func updateTripNotes(tripID: UUID, notes: String?) async throws { try write("updateTripNotes") }
    func setFlightTrip(flightID: UUID, tripID: UUID?) async throws { try write("setFlightTrip") }
    func setFlightTravelers(flightID: UUID, travelerIDs: [UUID]) async throws { try write("setFlightTravelers") }

    func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String {
        try write("uploadMemoryPhoto")
        uploadedPhotoCount += 1
        return "\(coupleID)/\(memoryID)/\(UUID()).jpg"
    }
    func insertMemory(coupleID: UUID, memory: Memory, photoPaths: [String]) async throws -> [MemoryPhoto] {
        try write("insertMemory")
        insertedMemories.append(memory.id)
        return photoPaths.map { MemoryPhoto(id: UUID(), path: $0, url: URL(string: "https://example.invalid/\($0)")!) }
    }
    func updateMemory(_ edit: MemoryEdit) async throws {
        duringUpdateMemory?()
        try write("updateMemory")
        updatedMemories.append(edit)
        if let index = serverMemories.firstIndex(where: { $0.id == edit.memoryID }) {
            edit.apply(to: &serverMemories[index])
        }
    }
    func addMemoryPhotos(memoryID: UUID, photoPaths: [String], startingPosition: Int) async throws -> [MemoryPhoto] {
        try write("addMemoryPhotos")
        return photoPaths.map { MemoryPhoto(id: UUID(), path: $0, url: URL(string: "https://example.invalid/\($0)")!) }
    }
    func deleteMemoryPhoto(id: UUID, path: String) async throws { try write("deleteMemoryPhoto") }
    func setMemoryTrip(memoryID: UUID, tripID: UUID?) async throws {
        try write("setMemoryTrip")
        memoryTripLinks.append((memoryID, tripID))
    }

    func updateFirstName(_ name: String) async throws {
        await beforeUpdateFirstName?()
        try write("updateFirstName")
        firstNames.append(name)
    }
    func updatePartnerNickname(_ name: String) async throws { try write("updatePartnerNickname") }
    func updatePartnerHomeCityGuess(_ place: Place) async throws { try write("updatePartnerHomeCityGuess") }
    func updateHomeCity(_ place: Place) async throws {
        try write("updateHomeCity")
        homeCities.append(place)
    }
    func updateAnniversaryDate(_ date: Date) async throws { try write("updateAnniversaryDate") }
    func updateCoupleAnniversaryDate(coupleID: UUID, date: Date) async throws { try write("updateCoupleAnniversaryDate") }
}

extension PendingMemoryDiskTests {
    @Suite("Writes made offline are kept and sent later", .serialized)
    @MainActor
    struct OfflineOutboxTests {

        private let samplePhoto = Data([0xFF, 0xD8, 0xFF, 0xDB] + Array(repeating: 0x42, count: 512))
        private let rome = Place(city: "Rome", country: "Italy", latitude: 41.9, longitude: 12.5)
        private let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.81, longitude: 144.96)

        /// A paired model on a backend that is down, with every on-disk queue empty.
        private func pairedOfflineModel() -> (AppModel, FakeCoupleDataBackend) {
            AppModel.clearPersistedAccountState()
            let model = AppModel()
            let backend = FakeCoupleDataBackend()
            backend.isOffline = true
            model.backend = backend
            model.setBackendCoupleIDForTesting(UUID())
            return (model, backend)
        }

        private func syncedMemory(title: String = "Where we met") -> Memory {
            Memory(title: title, place: rome, date: Date(timeIntervalSince1970: 1_700_000_000), note: "")
        }

        private func syncedTrip() -> Trip {
            Trip(
                travelerIDs: [],
                origin: melbourne,
                destination: rome,
                departureDate: Date().addingTimeInterval(86_400),
                arrivalDate: Date().addingTimeInterval(864_000),
                category: .together,
                distanceKm: 15_000
            )
        }

        // MARK: - New memories and trips (CORE-2, HOME-1, 5-home-NEW-2, 1-core-NEW-2)

        @Test("a memory added while paired and offline is written to disk, with its photos showing")
        func pairedOfflineMemoryIsPersisted() async {
            let (model, _) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }

            let memory = await model.addMemory(title: "Where we met", place: rome, date: .now, note: "", imagesData: [samplePhoto])

            let onDisk = PendingMemoryStore.loadAll().first { $0.memory.id == memory.id }
            #expect(onDisk != nil, "kept in memory only, it is gone if the app is killed before it is sent")
            #expect(onDisk?.photosData.count == 1)
            #expect(model.memories.first { $0.id == memory.id }?.photos.count == 1, "the photo should show while it waits")
        }

        @Test("a refresh does not drop a memory that has not been sent yet")
        func refreshKeepsPendingMemory() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let other = syncedMemory(title: "Partner's memory")
            backend.serverMemories = [other]

            let memory = await model.addMemory(title: "Where we met", place: rome, date: .now, note: "", imagesData: [])
            await model.refreshMemories()

            #expect(model.memories.contains { $0.id == memory.id }, "the refresh replaced the list and took the unsent memory with it")
            #expect(model.memories.contains { $0.id == other.id })
        }

        @Test("a memory drafted before pairing survives the first refresh after pairing")
        func soloDraftSurvivesRefresh() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            let backend = FakeCoupleDataBackend()
            model.backend = backend
            let memory = await model.addMemory(title: "Before you joined", place: nil, date: .now, note: "", imagesData: [])

            // Paired, and the flush that would have sent it failed, so it is still pending.
            model.setBackendCoupleIDForTesting(UUID())
            await model.refreshMemories()

            #expect(model.memories.contains { $0.id == memory.id })
        }

        @Test("a refresh does not drop a trip that has not been sent yet")
        func refreshKeepsPendingTrip() async {
            let (model, _) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }

            let trip = await model.addTrip(origin: melbourne, destination: rome, departureDate: .now, arrivalDate: .now.addingTimeInterval(86_400), traveler: .you, category: .together)
            await model.refreshTrips()

            #expect(model.trips.contains { $0.id == trip.id })
            #expect(PendingTripStore.loadAll().contains { $0.id == trip.id })
        }

        // MARK: - Edits (CORE-3, HOME-2)

        @Test("an edit to a memory made offline survives a refresh and is sent on the next sync")
        func memoryEditIsQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let original = syncedMemory()
            backend.serverMemories = [original]
            await model.refreshMemories()

            var edited = original
            edited.title = "Where we really met"
            await model.updateMemory(edited)
            await model.refreshMemories()
            #expect(model.memories.first { $0.id == original.id }?.title == "Where we really met", "the refresh put the server's old title back")

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.updatedMemories.last?.title == "Where we really met", "the edit was never sent again")

            // Sent once, and gone from the queue.
            await model.syncPendingWrites()
            #expect(backend.updatedMemories.count == 1)
        }

        @Test("an edit to a trip made offline survives a refresh and is sent on the next sync")
        func tripEditIsQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let original = syncedTrip()
            backend.serverTrips = [original]
            await model.refreshTrips()

            var edited = original
            edited.category = .reunion
            await model.updateTrip(edited)
            await model.refreshTrips()
            #expect(model.trips.first { $0.id == original.id }?.category == .reunion)

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.updatedTrips.last?.category == .reunion)
        }

        @Test("linking a memory to a trip offline is kept and sent")
        func memoryLinkIsQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let memory = syncedMemory()
            let trip = syncedTrip()
            backend.serverMemories = [memory]
            backend.serverTrips = [trip]
            await model.refreshMemories()
            await model.refreshTrips()

            await model.linkMemory(memory, to: trip)
            await model.refreshMemories()
            #expect(model.memories.first { $0.id == memory.id }?.tripID == trip.id)

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.memoryTripLinks.last?.tripID == trip.id)
        }

        @Test("photos added to an existing memory offline show, and are uploaded on the next sync")
        func photosAddedOfflineAreQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let memory = syncedMemory()
            backend.serverMemories = [memory]
            await model.refreshMemories()

            await model.updateMemory(memory, newImagesData: [samplePhoto])
            await model.refreshMemories()
            #expect(model.memories.first { $0.id == memory.id }?.photos.count == 1, "picked offline, the photo vanished")

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.uploadedPhotoCount == 1)
            #expect(backend.calls.contains("addMemoryPhotos"))
            let photos = model.memories.first { $0.id == memory.id }?.photos ?? []
            #expect(photos.count == 1, "the local copy should be replaced by the uploaded one, not added to")
            #expect(photos.first?.path != "pending")
        }

        @Test("a change to your own name or city made offline is kept and sent")
        func profileEditsAreQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }

            await model.updateProfile(name: "Alex")
            await model.setHomeCity(for: model.currentUser.id, city: rome)
            #expect(model.currentUser.name == "Alex")
            #expect(model.currentUser.homeCity?.city == "Rome", "the city picker didn't show the change")

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.firstNames == ["Alex"])
            #expect(backend.homeCities.map(\.city) == ["Rome"])
        }

        @Test("a queued edit survives the app being relaunched")
        func queueSurvivesRelaunch() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let original = syncedMemory()
            backend.serverMemories = [original]
            await model.refreshMemories()
            var edited = original
            edited.note = "Written on the plane"
            await model.updateMemory(edited)

            let relaunched = AppModel()
            let onlineBackend = FakeCoupleDataBackend()
            onlineBackend.serverMemories = [original]
            relaunched.backend = onlineBackend
            relaunched.setBackendCoupleIDForTesting(UUID())
            await relaunched.syncPendingWrites()

            #expect(onlineBackend.updatedMemories.last?.note == "Written on the plane")
        }

        @Test("a refused edit is rolled back and not queued")
        func refusedEditIsNotQueued() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let original = syncedMemory()
            backend.serverMemories = [original]
            backend.isOffline = false
            await model.refreshMemories()

            backend.isRefusing = true
            var edited = original
            edited.title = "Refused"
            await model.updateMemory(edited)
            #expect(model.memories.first { $0.id == original.id }?.title == original.title)
            #expect(model.writeRefusedMessage != nil)

            backend.isRefusing = false
            await model.syncPendingWrites()
            #expect(backend.updatedMemories.isEmpty, "a refusal will never land, so it must not be retried")
        }

        @Test("an unsent edit does not survive sign-out")
        func queueIsClearedOnSignOut() {
            AppModel.clearPersistedAccountState()
            PendingWriteStore.add(.firstName("Someone else"))
            #expect(PendingWriteStore.all().count == 1, "precondition: the queue persists")

            AppModel.clearPersistedAccountState()

            #expect(PendingWriteStore.all().isEmpty, "the next account would send it as themselves")
        }

        @Test("a second edit to the same field replaces the first in the queue")
        func editsCoalesce() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            await model.updateProfile(name: "Al")
            await model.updateProfile(name: "Alex")
            #expect(PendingWriteStore.all().count == 1)

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.firstNames == ["Alex"])
        }

        @Test("deleting a memory drops its queued edits, rather than sending them to a missing row")
        func deleteDropsQueuedEdits() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            let memory = syncedMemory()
            backend.serverMemories = [memory]
            await model.refreshMemories()
            var edited = memory
            edited.title = "Renamed"
            await model.updateMemory(edited)

            await model.deleteMemory(memory)

            #expect(PendingWriteStore.all().isEmpty)
        }

        // MARK: - 1-core-NEW-1

        @Test("photos from an edit land on the edited memory even if the list changed mid-save")
        func photosLandOnTheRightMemory() async {
            let (model, backend) = pairedOfflineModel()
            defer { AppModel.clearPersistedAccountState() }
            backend.isOffline = false
            let edited = syncedMemory(title: "Edited")
            let newcomer = syncedMemory(title: "Arrived during the save")
            backend.serverMemories = [edited]
            await model.refreshMemories()

            // A refresh landing while the save is in the air, with a new memory ahead of this one.
            backend.duringUpdateMemory = { [weak model] in
                model?.memories.insert(newcomer, at: 0)
            }
            var changed = edited
            changed.title = "Edited again"
            await model.updateMemory(changed, newImagesData: [samplePhoto])

            #expect(model.memories.first { $0.id == edited.id }?.photos.count == 1)
            #expect(model.memories.first { $0.id == newcomer.id }?.photos.isEmpty == true, "the photo went to whichever memory took its old index")
        }
    }
}
