//
//  CoupleDataExporter.swift
//  Twofold
//
//  Everything a couple made together, as a folder of files anyone can open without this app.
//
//  Written for the case where it matters most: a dissolved relationship with a deadline on it. An
//  archive is permanently deleted 90 days after it ends, so this is the last chance anyone gets to
//  keep what is in it, and the output has to be readable in ten years by someone who has never
//  heard of Twofold. Hence CSV and JPEG and PDF, not a database dump.
//
//    export/
//      trips.csv
//      memories.csv
//      flights.csv
//      games.csv
//      relationship-record.pdf
//      media/            one file per memory photo, named as memories.csv lists it
//      README.txt        what the files are, and what the columns mean
//
//  Zipped through NSFileCoordinator's `.forUploading` option, which produces a real zip from a
//  directory with no third-party dependency — the same mechanism the Files app uses for "Compress".
//

import Foundation
import SwiftUI

enum CoupleDataExporter {

    enum ExportError: LocalizedError {
        case couldNotCreateFolder
        case couldNotZip

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFolder: "Couldn't prepare the export. Try again."
            case .couldNotZip: "Couldn't finish packaging the export. Try again."
            }
        }
    }

    /// What was gathered, so the caller can say what it did rather than just handing over a file.
    struct Result {
        var url: URL
        var tripCount: Int
        var memoryCount: Int
        var flightCount: Int
        var gameCount: Int
        var photoCount: Int
        /// Photos that could not be downloaded. Surfaced rather than swallowed: someone exporting
        /// before a deadline needs to know their pictures did not all make it.
        var missingPhotoCount: Int
    }

    /// Builds the export and returns a zip in the caller's temporary directory.
    ///
    /// `partnerNames` maps profile ids to names so the CSVs say who travelled rather than printing
    /// UUIDs. Anyone not in it — a deleted account, say — reads as "Unknown".
    static func export(
        coupleID: UUID,
        partnerNames: [UUID: String],
        title: String,
        selfName: String,
        partnerName: String,
        progress: @MainActor (String) -> Void = { _ in }
    ) async throws -> Result {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("twofold-export-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(folderName(for: title), isDirectory: true)
        let media = folder.appendingPathComponent("media", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        } catch {
            throw ExportError.couldNotCreateFolder
        }

        await progress("Gathering your history…")

        // Each of these is allowed to fail without sinking the export: a missing table is better
        // than no export at all when the alternative is losing everything to a deadline.
        async let tripsTask = (try? await BackendService.fetchTrips(coupleID: coupleID)) ?? []
        async let memoriesTask = (try? await BackendService.fetchMemories(coupleID: coupleID)) ?? []
        async let flightsTask = (try? await BackendService.fetchFlights(coupleID: coupleID)) ?? []
        async let gamesTask = (try? await BackendService.fetchExportedGameSessions(coupleID: coupleID)) ?? []

        let trips = await tripsTask
        let memories = await memoriesTask
        let flights = await flightsTask
        let games = await gamesTask

        let nameFor: (UUID) -> String = { partnerNames[$0] ?? "Unknown" }

        try write(
            CSVWriter.file(
                header: CoupleDataTables.tripHeader,
                rows: trips.map { CoupleDataTables.tripRow($0, nameFor: nameFor) }
            ),
            to: folder.appendingPathComponent("trips.csv")
        )

        try write(
            CSVWriter.file(
                header: CoupleDataTables.flightHeader,
                rows: flights.map { CoupleDataTables.flightRow($0, nameFor: nameFor) }
            ),
            to: folder.appendingPathComponent("flights.csv")
        )

        try write(
            CSVWriter.file(
                header: CoupleDataTables.gameHeader,
                rows: games.map(CoupleDataTables.gameRow)
            ),
            to: folder.appendingPathComponent("games.csv")
        )

        // Memories last of the four, because their rows carry the names of the files written
        // alongside them and those only exist once the photos are down.
        await progress("Saving photos…")
        var memoryRows: [[String]] = []
        var photoCount = 0
        var missingPhotoCount = 0

        for (index, memory) in memories.enumerated() {
            var fileNames: [String] = []
            for (photoIndex, photo) in memory.photos.enumerated() {
                let name = photoFileName(memoryIndex: index, photoIndex: photoIndex, url: photo.url)
                if await downloadPhoto(from: photo.url, to: media.appendingPathComponent(name)) {
                    fileNames.append(name)
                    photoCount += 1
                } else {
                    missingPhotoCount += 1
                }
            }
            memoryRows.append(CoupleDataTables.memoryRow(memory, photoFiles: fileNames))
        }

        try write(
            CSVWriter.file(header: CoupleDataTables.memoryHeader, rows: memoryRows),
            to: folder.appendingPathComponent("memories.csv")
        )

        // The readable half. Best-effort: the CSVs and photos are the record that matters, and a
        // PDF that fails to render must not cost someone the export they were running against a
        // deadline. Its absence is noted in the README rather than thrown.
        await progress("Writing the relationship record…")
        var pdfIncluded = false
        if let pdfURL = await relationshipRecord(
            trips: trips, memories: memories, flights: flights,
            selfName: selfName, partnerName: partnerName
        ) {
            let destination = folder.appendingPathComponent("relationship-record.pdf")
            if (try? FileManager.default.copyItem(at: pdfURL, to: destination)) != nil {
                pdfIncluded = true
            }
        }

        try write(
            Data(readme(title: title, missingPhotoCount: missingPhotoCount, pdfIncluded: pdfIncluded).utf8),
            to: folder.appendingPathComponent("README.txt")
        )

        await progress("Packaging…")
        let zip = try zipped(folder, named: folderName(for: title))

        return Result(
            url: zip,
            tripCount: trips.count,
            memoryCount: memories.count,
            flightCount: flights.count,
            gameCount: games.count,
            photoCount: photoCount,
            missingPhotoCount: missingPhotoCount
        )
    }

    /// The PDF, built from the same rows as the CSVs.
    ///
    /// A trip carries its own flights and memories rather than them also appearing as top-level
    /// entries — that is what `ExportTimelineItem` is shaped for, and without it a trip with two
    /// legs and six photos reads as nine separate events in the same afternoon.
    @MainActor
    private static func relationshipRecord(
        trips: [Trip],
        memories: [Memory],
        flights: [Flight],
        selfName: String,
        partnerName: String
    ) async -> URL? {
        let memoriesByTrip = Dictionary(grouping: memories.filter { $0.tripID != nil }, by: { $0.tripID! })
        let flightsByTrip = Dictionary(grouping: flights.filter { $0.tripID != nil }, by: { $0.tripID! })

        var items: [ExportTimelineItem] = trips.map { trip in
            .trip(
                trip,
                description: trip.notes ?? "",
                linkedFlights: (flightsByTrip[trip.id] ?? []).map {
                    .init(flight: $0, includeAttachments: false, attachments: [])
                },
                linkedMemories: (memoriesByTrip[trip.id] ?? []).map {
                    .init(memory: $0, description: $0.note)
                }
            )
        }
        items += memories.filter { $0.tripID == nil }.map { .memory($0, description: $0.note) }
        items += flights.filter { $0.tripID == nil }.map { .flight($0, includeAttachments: false, attachments: []) }

        guard !items.isEmpty else { return nil }

        return try? await CoupleHistoryPDFExporter.generate(
            selfName: selfName,
            partnerName: partnerName,
            selfPhotoURL: nil,
            partnerPhotoURL: nil,
            items: items
        )
    }

    // MARK: - Pieces

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    /// Indexed by position rather than named after the memory's title, which can be empty,
    /// duplicated, or full of characters no filesystem wants. The index is what `memories.csv`
    /// prints, so the two always agree.
    static func photoFileName(memoryIndex: Int, photoIndex: Int, url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        return String(format: "memory-%04d-%02d.%@", memoryIndex + 1, photoIndex + 1, ext)
    }

    /// A folder name a filesystem will accept, from a partner's name that might contain anything.
    static func folderName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        let base = cleaned.isEmpty ? "twofold" : cleaned.lowercased()
        return "\(base)-twofold-export"
    }

    private static func downloadPhoto(from url: URL, to destination: URL) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return false
            }
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// `.forUploading` hands the coordinator's block a zip of the directory, in a location it owns
    /// and reclaims. It is copied out before the block returns, which is the whole reason this is
    /// synchronous inside — the temporary file is gone the moment the block exits.
    private static func zipped(_ folder: URL, named name: String) throws -> URL {
        var coordinatorError: NSError?
        var copied: URL?
        var copyError: Error?

        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zipURL in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipURL, to: destination)
                copied = destination
            } catch {
                copyError = error
            }
        }

        if coordinatorError != nil || copyError != nil { throw ExportError.couldNotZip }
        guard let copied else { throw ExportError.couldNotZip }
        return copied
    }

    /// Written for someone opening this years later with no idea what made it.
    private static func readme(title: String, missingPhotoCount: Int, pdfIncluded: Bool) -> String {
        var text = """
        \(title) — Twofold export
        Created \(Date().formatted(date: .long, time: .shortened))

        WHAT'S HERE

        trips.csv       Every trip, with where and when, who travelled, and the distance.
        memories.csv    Every memory, with its place and date. The photo_files column lists
                        the files in media/ that belong to each one.
        flights.csv     Every tracked flight: route, times as scheduled and as flown, delays.
        games.csv       Every game session played together.
        media/          The photos, named as memories.csv lists them.

        NOTES

        Times are ISO 8601 and keep their UTC offset, so they mean the same thing wherever
        they are read. Dates without a time (a memory's day, an anniversary) are plain
        YYYY-MM-DD.

        The CSVs are UTF-8 with a byte order mark, which is what lets Excel on Windows show
        accented place names correctly.

        Some fields begin with an apostrophe. That is deliberate: text starting with =, +, -
        or @ is treated as a formula by spreadsheet apps, and the apostrophe tells them to
        read it as text. Remove it to see the original.

        The ids in these files are the app's own. They are there so the files can be matched
        up with each other — a memory's trip_id is the trip_id of a row in trips.csv.
        """

        if pdfIncluded {
            text += """


            relationship-record.pdf is a readable version of the same history — for looking at
            rather than working with. Everything in it is also in the CSVs.
            """
        }

        if missingPhotoCount > 0 {
            text += """


            MISSING PHOTOS

            \(missingPhotoCount) photo\(missingPhotoCount == 1 ? "" : "s") could not be downloaded
            when this export was made, most likely because the connection dropped partway. They are
            listed in memories.csv but are not in media/. Running the export again on a better
            connection should get them.
            """
        }

        return text + "\n"
    }
}
