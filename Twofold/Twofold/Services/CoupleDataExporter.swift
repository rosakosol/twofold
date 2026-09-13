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

    /// What to put in the export, and how.
    ///
    /// Defaults to everything as CSV with the PDF, which is what the archive export has always
    /// produced — so `ArchivedDataView`, which is running against a deletion deadline and should
    /// not be asking anyone to make choices, keeps its existing behaviour by passing nothing.
    /// `ExportDataView` is the screen that fills this in.
    struct Options: Equatable {
        /// How the tables are written. CSV opens in a spreadsheet; JSON is the "structured,
        /// commonly used and machine-readable" form a portability request is entitled to, which a
        /// CSV per table is arguably not.
        enum DataFormat: String, CaseIterable, Identifiable {
            case csv, json
            var id: String { rawValue }
            var label: String { self == .csv ? "Spreadsheets (CSV)" : "Data file (JSON)" }
            var fileExtension: String { rawValue }
        }

        /// The readable copy alongside the data, if any.
        enum Document: String, CaseIterable, Identifiable {
            case none, pdf, word
            var id: String { rawValue }
            var label: String {
                switch self {
                case .none: "None"
                case .pdf: "PDF"
                case .word: "Word"
                }
            }
        }

        var trips = true
        var memories = true
        var flights = true
        var games = true
        /// Only meaningful alongside `memories` — the photos belong to them.
        var photos = true
        var dataFormat: DataFormat = .csv
        var document: Document = .pdf

        /// Nothing to build. The UI disables the button on this rather than producing an empty zip.
        var isEmpty: Bool { !trips && !memories && !flights && !games && document == .none }

        static let everything = Options()
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

        /// Says what actually came out, including what didn't. Lives here rather than on either
        /// screen so the archive export and the current-couple export cannot describe the same
        /// result in two different ways.
        var summary: String {
            var parts: [String] = []
            if tripCount > 0 { parts.append("\(tripCount) trips") }
            if memoryCount > 0 { parts.append("\(memoryCount) memories") }
            if photoCount > 0 { parts.append("\(photoCount) photos") }
            if flightCount > 0 { parts.append("\(flightCount) flights") }
            if gameCount > 0 { parts.append("\(gameCount) games") }
            let body = parts.isEmpty ? "Ready." : "Ready — " + parts.joined(separator: ", ") + "."
            guard missingPhotoCount > 0 else { return body }
            return body + " \(missingPhotoCount) photo\(missingPhotoCount == 1 ? "" : "s") couldn't be downloaded — try again on a better connection to get \(missingPhotoCount == 1 ? "it" : "them")."
        }
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
        options: Options = .everything,
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
        //
        // The record needs trips, memories and flights whatever the tick boxes say, so those three
        // are fetched when either the table or the document wants them. Nothing is fetched that
        // nothing will read.
        let wantsRecord = options.document != .none
        async let tripsTask = (options.trips || wantsRecord)
            ? ((try? await BackendService.fetchTrips(coupleID: coupleID)) ?? []) : []
        async let memoriesTask = (options.memories || wantsRecord)
            ? ((try? await BackendService.fetchMemories(coupleID: coupleID)) ?? []) : []
        async let flightsTask = (options.flights || wantsRecord)
            ? ((try? await BackendService.fetchFlights(coupleID: coupleID)) ?? []) : []
        async let gamesTask = options.games
            ? ((try? await BackendService.fetchExportedGameSessions(coupleID: coupleID)) ?? []) : []

        let trips = await tripsTask
        let memories = await memoriesTask
        let flights = await flightsTask
        let games = await gamesTask

        let nameFor: (UUID) -> String = { partnerNames[$0] ?? "Unknown" }

        if options.trips {
            try writeTable(
                header: CoupleDataTables.tripHeader,
                rows: trips.map { CoupleDataTables.tripRow($0, nameFor: nameFor) },
                named: "trips", in: folder, as: options.dataFormat
            )
        }

        if options.flights {
            try writeTable(
                header: CoupleDataTables.flightHeader,
                rows: flights.map { CoupleDataTables.flightRow($0, nameFor: nameFor) },
                named: "flights", in: folder, as: options.dataFormat
            )
        }

        if options.games {
            try writeTable(
                header: CoupleDataTables.gameHeader,
                rows: games.map(CoupleDataTables.gameRow),
                named: "games", in: folder, as: options.dataFormat
            )
        }

        // Memories last of the four, because their rows carry the names of the files written
        // alongside them and those only exist once the photos are down.
        let wantsPhotos = options.memories && options.photos
        if wantsPhotos { await progress("Saving photos…") }
        var memoryRows: [[String]] = []
        var photoCount = 0
        var missingPhotoCount = 0

        if options.memories {
            for (index, memory) in memories.enumerated() {
                var fileNames: [String] = []
                if wantsPhotos {
                    for (photoIndex, photo) in memory.photos.enumerated() {
                        let name = photoFileName(memoryIndex: index, photoIndex: photoIndex, url: photo.url)
                        if await downloadPhoto(from: photo.url, to: media.appendingPathComponent(name)) {
                            fileNames.append(name)
                            photoCount += 1
                        } else {
                            missingPhotoCount += 1
                        }
                    }
                }
                memoryRows.append(CoupleDataTables.memoryRow(memory, photoFiles: fileNames))
            }

            try writeTable(
                header: CoupleDataTables.memoryHeader, rows: memoryRows,
                named: "memories", in: folder, as: options.dataFormat
            )
        }

        // An empty media/ directory in the zip would suggest the photos failed rather than that
        // they were not asked for.
        if !wantsPhotos { try? FileManager.default.removeItem(at: media) }

        // The readable half. Best-effort: the CSVs and photos are the record that matters, and a
        // PDF that fails to render must not cost someone the export they were running against a
        // deadline. Its absence is noted in the README rather than thrown.
        var pdfIncluded = false
        if options.document != .none {
            await progress("Writing the relationship record…")
            let items = await RelationshipRecord.timeline(trips: trips, memories: memories, flights: flights)
            let source: URL? = switch options.document {
            case .pdf:
                await relationshipRecord(
                    trips: trips, memories: memories, flights: flights,
                    selfName: selfName, partnerName: partnerName
                )
            case .word:
                items.isEmpty ? nil : await RelationshipRecordWriter.rtf(
                    items: items, selfName: selfName, partnerName: partnerName
                )
            case .none:
                nil
            }
            if let source {
                let name = options.document == .word ? "relationship-record.rtf" : "relationship-record.pdf"
                let destination = folder.appendingPathComponent(name)
                if (try? FileManager.default.copyItem(at: source, to: destination)) != nil {
                    pdfIncluded = true
                }
            }
        }

        try write(
            Data(readme(title: title, options: options, missingPhotoCount: missingPhotoCount, recordIncluded: pdfIncluded).utf8),
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

    /// The half of the README that only applies to one of the two formats.
    private static func formatNotes(_ format: Options.DataFormat) -> String {
        switch format {
        case .csv:
            """
            The CSVs are UTF-8 with a byte order mark, which is what lets Excel on Windows show
            accented place names correctly.

            Some fields begin with an apostrophe. That is deliberate: text starting with =, +, -
            or @ is treated as a formula by spreadsheet apps, and the apostrophe tells them to
            read it as text. Remove it to see the original.
            """
        case .json:
            """
            The JSON files are UTF-8. Each is an array of objects whose keys are the column names
            you would have got in the CSV, so the two formats describe exactly the same thing.

            Every value is a string, including numbers and dates. That is deliberate: they are
            already formatted for reading (ISO 8601 timestamps, distances with their units), and
            re-typing them here would mean two different answers to what a column contains.
            """
        }
    }

    /// One table, written in whichever format was chosen.
    ///
    /// JSON is built from the same `header`/`rows` pair the CSV uses, so the two formats cannot
    /// describe different columns — the header becomes the keys. Values stay strings rather than
    /// being coerced to numbers and dates: every one of them is already formatted for a human
    /// reader (ISO 8601 timestamps, a distance with its unit), and guessing types here would mean
    /// two definitions of what a column contains.
    private static func writeTable(
        header: [String],
        rows: [[String]],
        named name: String,
        in folder: URL,
        as format: Options.DataFormat
    ) throws {
        let destination = folder.appendingPathComponent("\(name).\(format.fileExtension)")
        switch format {
        case .csv:
            try write(CSVWriter.file(header: header, rows: rows), to: destination)
        case .json:
            let objects = rows.map { row in
                Dictionary(uniqueKeysWithValues: zip(header, row).map { ($0, stripSpreadsheetGuard($1)) })
            }
            guard let data = try? JSONSerialization.data(
                withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ) else { throw ExportError.couldNotCreateFolder }
            try write(data, to: destination)
        }
    }

    /// CSV rows carry a leading apostrophe on anything a spreadsheet would mistake for a formula.
    /// JSON has no such problem, and leaving it in would put a stray quote in the data.
    private static func stripSpreadsheetGuard(_ value: String) -> String {
        guard value.hasPrefix("'"), value.count > 1 else { return value }
        let rest = value.dropFirst()
        return "=+-@".contains(rest.first!) ? String(rest) : value
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
        partnerName: String,
        selfPhotoURL: URL? = nil,
        partnerPhotoURL: URL? = nil
    ) async -> URL? {
        // One definition of what the record contains, shared with the timeline screen and the
        // Word export — see `RelationshipRecord.timeline`. It used to be assembled here, which was
        // fine while the PDF was the only reader of it.
        let items = RelationshipRecord.timeline(trips: trips, memories: memories, flights: flights)

        guard !items.isEmpty else { return nil }

        return try? await CoupleHistoryPDFExporter.generate(
            selfName: selfName,
            partnerName: partnerName,
            selfPhotoURL: selfPhotoURL,
            partnerPhotoURL: partnerPhotoURL,
            items: items
        )
    }

    /// The record on its own, for a couple who are still together.
    ///
    /// `export` above builds this as one file inside a folder of CSVs, photos and a README, because
    /// it is written for a relationship that has ended with a deletion deadline on it: the point
    /// there is that everything survives, in formats anyone can open in ten years. A couple who are
    /// still together want the document, not the archive — a zip of spreadsheets is not a keepsake,
    /// and packaging one would be answering a question nobody asked.
    ///
    /// So this shares the renderer and skips the rest: no CSVs, no photo downloads, no zip. It also
    /// passes both avatars, which `export` leaves nil — the cover page has always accepted them,
    /// and a record of a living relationship should have their faces on the front.
    ///
    /// Nil when there is nothing to record yet, rather than a cover page with no pages behind it.
    static func relationshipRecordPDF(
        coupleID: UUID,
        selfName: String,
        partnerName: String,
        selfPhotoURL: URL?,
        partnerPhotoURL: URL?,
        progress: @MainActor (String) -> Void = { _ in }
    ) async -> URL? {
        await progress("Gathering your history…")

        // Same tolerance as `export`: one failed fetch should cost that section, not the document.
        async let tripsTask = (try? await BackendService.fetchTrips(coupleID: coupleID)) ?? []
        async let memoriesTask = (try? await BackendService.fetchMemories(coupleID: coupleID)) ?? []
        async let flightsTask = (try? await BackendService.fetchFlights(coupleID: coupleID)) ?? []

        let trips = await tripsTask
        let memories = await memoriesTask
        let flights = await flightsTask

        await progress("Writing your record…")
        return await relationshipRecord(
            trips: trips,
            memories: memories,
            flights: flights,
            selfName: selfName,
            partnerName: partnerName,
            selfPhotoURL: selfPhotoURL,
            partnerPhotoURL: partnerPhotoURL
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
    private static func readme(title: String, options: Options, missingPhotoCount: Int, recordIncluded: Bool) -> String {
        let ext = options.dataFormat.fileExtension
        var contents: [String] = []
        if options.trips {
            contents.append("trips.\(ext)       Every trip, with where and when, who travelled, and the distance.")
        }
        if options.memories {
            contents.append(
                options.photos
                    ? "memories.\(ext)    Every memory, with its place and date. The photo_files column lists\n                the files in media/ that belong to each one."
                    : "memories.\(ext)    Every memory, with its place and date. Photos were not included in\n                this export, so photo_files is empty."
            )
        }
        if options.flights {
            contents.append("flights.\(ext)     Every tracked flight: route, times as scheduled and as flown, delays.")
        }
        if options.games {
            contents.append("games.\(ext)       Every game session played together.")
        }
        if options.memories && options.photos {
            contents.append("media/          The photos, named as the memories table lists them.")
        }
        if recordIncluded {
            contents.append(
                options.document == .word
                    ? "relationship-record.rtf   The readable version, as a Word document."
                    : "relationship-record.pdf   The readable version."
            )
        }

        var text = """
        \(title) — Twofold export
        Created \(Date().formatted(date: .long, time: .shortened))

        WHAT'S HERE

        \(contents.joined(separator: "\n"))

        NOTES

        Times are ISO 8601 and keep their UTC offset, so they mean the same thing wherever
        they are read. Dates without a time (a memory's day, an anniversary) are plain
        YYYY-MM-DD.

        \(formatNotes(options.dataFormat))

        The ids in these files are the app's own. They are there so the files can be matched
        up with each other — a memory's trip_id is the trip_id of a row in the trips table.
        """

        if recordIncluded {
            let name = options.document == .word ? "relationship-record.rtf" : "relationship-record.pdf"
            text += """


            \(name) is a readable version of the same history — for looking at rather than
            working with. Everything in it is also in the data files.
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
