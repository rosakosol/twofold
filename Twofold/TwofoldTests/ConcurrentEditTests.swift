//
//  ConcurrentEditTests.swift
//  TwofoldTests
//
//  Two people editing the same trip or memory (HOME-5, HOME-7).
//
//  An edit used to send every field the editor had, so whatever this phone's copy said about the
//  fields nobody touched went to the server too. A partner's change to one field was undone by an
//  edit to a different one, with nothing on either screen to say so. An edit now sends only what
//  changed, against the copy the editor started from.
//
//  `FakeCoupleDataBackend` keeps a server copy and applies each write to it the way PostgREST
//  would, so these assert on what the server ends up holding.
//
//  Nested under `PendingMemoryDiskTests` because these write to `PendingWriteStore`.
//

import Foundation
import Testing
@testable import Twofold

extension PendingMemoryDiskTests {
    @Suite("An edit sends only what it changed", .serialized)
    @MainActor
    struct ConcurrentEditTests {

        private let rome = Place(city: "Rome", country: "Italy", latitude: 41.9, longitude: 12.5)
        private let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.81, longitude: 144.96)
        private let tokyo = Place(city: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.69)

        private func pairedModel() -> (AppModel, FakeCoupleDataBackend) {
            AppModel.clearPersistedAccountState()
            let model = AppModel()
            let backend = FakeCoupleDataBackend()
            model.backend = backend
            model.setBackendCoupleIDForTesting(UUID())
            return (model, backend)
        }

        @Test("changing a memory's title leaves the note a partner has just written")
        func memoryTitleEditKeepsPartnersNote() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let memory = Memory(title: "Where we met", place: rome, date: Date(timeIntervalSince1970: 1_700_000_000), note: "")
            backend.serverMemories = [memory]
            await model.refreshMemories()

            // The partner's edit reaches the server, not yet this phone.
            backend.serverMemories[0].note = "The café by the station"
            var edited = model.memories[0]
            edited.title = "Where we really met"
            await model.updateMemory(edited)

            #expect(backend.serverMemories[0].title == "Where we really met")
            #expect(backend.serverMemories[0].note == "The café by the station", "the title edit sent this phone's old note and wiped the partner's")
        }

        /// HOME-5: the full editor saves the copy it opened with. A partner's edit that reached
        /// this phone while the sheet was open, and a photo removed from the sheet, must survive.
        @Test("saving the full editor applies only what was changed in it")
        func editorSavesOnlyItsChanges() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let kept = MemoryPhoto(id: UUID(), path: "c/m/kept.jpg", url: URL(string: "https://example.invalid/kept.jpg")!)
            let removed = MemoryPhoto(id: UUID(), path: "c/m/removed.jpg", url: URL(string: "https://example.invalid/removed.jpg")!)
            var memory = Memory(title: "Where we met", place: rome, date: Date(timeIntervalSince1970: 1_700_000_000), note: "")
            memory.photos = [kept, removed]
            backend.serverMemories = [memory]
            await model.refreshMemories()

            // The sheet opens with this copy.
            let opened = model.memories[0]
            // While it is open: a photo is removed from it, and the partner's note arrives.
            await model.removePhoto(removed, from: opened)
            backend.serverMemories[0].note = "The café by the station"
            backend.serverMemories[0].photos = [kept]
            await model.refreshMemories()

            var edited = opened
            edited.title = "Where we really met"
            await model.updateMemory(edited, from: opened)

            let shown = model.memories.first { $0.id == memory.id }
            #expect(shown?.title == "Where we really met")
            #expect(shown?.note == "The café by the station", "the sheet's old note went back on screen")
            #expect(shown?.photos.map(\.id) == [kept.id], "the removed photo came back")
            #expect(backend.serverMemories[0].note == "The café by the station", "and to the server")
            #expect(backend.updatedMemories.last == MemoryEdit(memoryID: memory.id, title: "Where we really met"))
        }

        @Test("two edits queued offline to different fields both reach the server")
        func queuedEditsMerge() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let memory = Memory(title: "Where we met", place: rome, date: Date(timeIntervalSince1970: 1_700_000_000), note: "")
            backend.serverMemories = [memory]
            await model.refreshMemories()

            backend.isOffline = true
            var first = model.memories[0]
            first.title = "Where we really met"
            await model.updateMemory(first)
            var second = model.memories[0]
            second.note = "Written on the plane"
            await model.updateMemory(second)
            #expect(PendingWriteStore.all().count == 1, "one entry per memory")

            backend.isOffline = false
            await model.syncPendingWrites()
            #expect(backend.serverMemories[0].title == "Where we really met", "the second edit replaced the first and lost its title")
            #expect(backend.serverMemories[0].note == "Written on the plane")
        }

        @Test("an edit queued by an older build, with every field, is still sent")
        func legacyWholeRowEditIsSent() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            var memory = Memory(title: "Where we met", place: rome, date: Date(timeIntervalSince1970: 1_700_000_000), note: "")
            backend.serverMemories = [memory]
            memory.title = "Queued before the update"
            PendingWriteStore.add(.memory(memory))

            await model.syncPendingWrites()

            #expect(backend.serverMemories[0].title == "Queued before the update")
            #expect(PendingWriteStore.all().isEmpty)
        }

        @Test("a refused edit puts back only the field it changed")
        func refusalUndoesOnlyItsField() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let trip = Trip(
                travelerIDs: [],
                origin: melbourne,
                destination: rome,
                departureDate: Date().addingTimeInterval(86_400),
                arrivalDate: Date().addingTimeInterval(864_000),
                category: .together,
                distanceKm: 15_000
            )
            backend.serverTrips = [trip]
            await model.refreshTrips()

            backend.isRefusing = true
            var edited = model.trips[0]
            edited.category = .reunion
            await model.updateTrip(edited)

            #expect(model.trips[0].category == .together)
            #expect(model.writeRefusedMessage != nil)
        }

        @Test("changing a trip's category leaves the notes a partner has just written")
        func tripCategoryEditKeepsPartnersNotes() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let trip = Trip(
                travelerIDs: [],
                origin: melbourne,
                destination: rome,
                departureDate: Date().addingTimeInterval(86_400),
                arrivalDate: Date().addingTimeInterval(864_000),
                category: .together,
                distanceKm: 15_000
            )
            backend.serverTrips = [trip]
            await model.refreshTrips()

            backend.serverTrips[0].notes = "Ferry at six"
            var edited = model.trips[0]
            edited.category = .reunion
            await model.updateTrip(edited)

            #expect(backend.serverTrips[0].category == .reunion)
            #expect(backend.serverTrips[0].notes == "Ferry at six", "the category edit sent this phone's empty notes and wiped the partner's")
        }

        @Test("changing a trip's destination leaves the dates a partner has just moved")
        func tripDestinationEditKeepsPartnersDates() async {
            let (model, backend) = pairedModel()
            defer { AppModel.clearPersistedAccountState() }
            let trip = Trip(
                travelerIDs: [],
                origin: melbourne,
                destination: rome,
                departureDate: Date(timeIntervalSince1970: 1_800_000_000),
                arrivalDate: Date(timeIntervalSince1970: 1_800_100_000),
                category: .together,
                distanceKm: 15_000
            )
            backend.serverTrips = [trip]
            await model.refreshTrips()

            let moved = Date(timeIntervalSince1970: 1_810_000_000)
            backend.serverTrips[0].departureDate = moved
            var edited = model.trips[0]
            edited.destination = tokyo
            await model.updateTrip(edited)

            #expect(backend.serverTrips[0].destination.city == "Tokyo")
            #expect(backend.serverTrips[0].departureDate == moved, "the destination edit moved the partner's departure back")
        }
    }
}
