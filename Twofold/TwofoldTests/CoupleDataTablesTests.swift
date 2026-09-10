//
//  CoupleDataTablesTests.swift
//  TwofoldTests
//
//  The CSV tables in a data export.
//
//  The failure worth guarding against here is quiet: a row that has one more or one fewer column
//  than its header shifts every value after it, and a spreadsheet opens it without complaint. Every
//  date lands in the notes column and nobody notices until they go looking for something years
//  later, by which time the archive it came from has been deleted.
//
//  So each table asserts width against its own header, and the ids that let the files be joined
//  back together are asserted present rather than assumed.
//

import Testing
import Foundation
@testable import Twofold

struct CoupleDataTablesTests {

    private static let ann = UUID()
    private static let ben = UUID()

    private func name(_ id: UUID) -> String {
        switch id {
        case Self.ann: "Ann"
        case Self.ben: "Ben"
        default: "Unknown"
        }
    }

    private func place(_ city: String, _ country: String, iata: String? = nil) -> Place {
        Place(id: UUID(), city: city, country: country, iataCode: iata, latitude: 1.5, longitude: 2.5)
    }

    private func trip(notes: String? = nil) -> Trip {
        Trip(
            id: UUID(),
            travelerIDs: [Self.ann, Self.ben],
            origin: place("Melbourne", "Australia", iata: "MEL"),
            destination: place("Rome", "Italy", iata: "FCO"),
            departureDate: Date(timeIntervalSince1970: 1_790_000_000),
            arrivalDate: Date(timeIntervalSince1970: 1_790_100_000),
            category: .reunion,
            distanceKm: 16_000,
            notes: notes
        )
    }

    private func memory(title: String = "The airport", note: String = "", photos: Int = 0) -> Memory {
        Memory(
            id: UUID(),
            title: title,
            place: place("Rome", "Italy"),
            date: Date(timeIntervalSince1970: 1_790_000_000),
            note: note,
            photoSeed: 1,
            photos: (0..<photos).map { MemoryPhoto(id: UUID(), path: "p\($0)", url: URL(string: "https://x/\($0)")!) }
        )
    }

    // MARK: - Every row matches its header

    @Test("a trip row is exactly as wide as the trip header")
    func tripWidth() {
        #expect(CoupleDataTables.tripRow(trip(), nameFor: name).count == CoupleDataTables.tripHeader.count)
        #expect(CoupleDataTables.tripRow(trip(notes: "bring the good camera"), nameFor: name).count
                == CoupleDataTables.tripHeader.count)
    }

    /// With and without a place, which is the field most likely to be nil — a memory need not have
    /// one, and three columns depend on it.
    @Test("a memory row is exactly as wide as the memory header, place or no place")
    func memoryWidth() {
        var placeless = memory()
        placeless.place = nil
        #expect(CoupleDataTables.memoryRow(memory(), photoFiles: []).count == CoupleDataTables.memoryHeader.count)
        #expect(CoupleDataTables.memoryRow(placeless, photoFiles: []).count == CoupleDataTables.memoryHeader.count)
    }

    @Test("a game row is exactly as wide as the game header")
    func gameWidth() {
        let session = ExportedGameSession(
            id: UUID(), gameType: "deep_conversations", deckTitle: nil,
            startedAt: nil, status: "completed", roundsCompleted: 3, roundsTotal: 5
        )
        #expect(CoupleDataTables.gameRow(session).count == CoupleDataTables.gameHeader.count)
    }

    // MARK: - The files can be joined back together

    /// A memory's `trip_id` and a trip's `trip_id` are what let someone reassemble the story from
    /// four flat files. If either goes missing the export is a pile of unrelated rows.
    @Test("ids that join the files are written")
    func joiningIdsArePresent() {
        let aTrip = trip()
        var aMemory = memory()
        aMemory.tripID = aTrip.id

        let tripRow = CoupleDataTables.tripRow(aTrip, nameFor: name)
        let memoryRow = CoupleDataTables.memoryRow(aMemory, photoFiles: [])

        #expect(tripRow[CoupleDataTables.tripHeader.firstIndex(of: "trip_id")!] == aTrip.id.uuidString)
        #expect(memoryRow[CoupleDataTables.memoryHeader.firstIndex(of: "trip_id")!] == aTrip.id.uuidString)
    }

    /// Names, not raw UUIDs. A column of `8B3F...` tells the reader nothing about who travelled.
    @Test("travellers are written as names")
    func travellersAreNamed() {
        let row = CoupleDataTables.tripRow(trip(), nameFor: name)
        let travellers = row[CoupleDataTables.tripHeader.firstIndex(of: "travellers")!]
        #expect(travellers == "Ann; Ben")
    }

    /// The photo files named in the CSV are the ones written into `media/`, so the two halves of
    /// the export can be matched by hand.
    @Test("photo file names are carried into the row")
    func photoFilesAreListed() {
        let row = CoupleDataTables.memoryRow(memory(photos: 2), photoFiles: ["mem-1-0.jpg", "mem-1-1.jpg"])
        #expect(row[CoupleDataTables.memoryHeader.firstIndex(of: "photo_files")!] == "mem-1-0.jpg; mem-1-1.jpg")
        #expect(row[CoupleDataTables.memoryHeader.firstIndex(of: "photo_count")!] == "2")
    }

    // MARK: - Content that would break a naive writer

    /// The whole reason `CSVWriter` exists, exercised through a real row: a memory whose title and
    /// note contain the two characters that break CSV, written by someone who had no idea their
    /// words would end up in a spreadsheet.
    @Test("a memory full of commas and quotes survives the round trip")
    func awkwardMemory() throws {
        let awkward = memory(
            title: #"Rome, at last"#,
            note: "He said \"we made it\"\nand then it rained"
        )
        let data = CSVWriter.file(
            header: CoupleDataTables.memoryHeader,
            rows: [CoupleDataTables.memoryRow(awkward, photoFiles: [])]
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(#""Rome, at last""#), "the comma in the title was not quoted")
        #expect(text.contains(#"""we made it"""#), "the quotes in the note were not doubled")
        // The header is one line; the body row must not have become several.
        #expect(text.components(separatedBy: "\r\n").count == 3, "the row broke across lines")
    }
}
