//
//  CoupleDataTables.swift
//  Twofold
//
//  The rows of the CSV files in a data export: what columns each kind gets, and what goes in them.
//
//  Separated from the file writing and the zipping so it can be tested without a filesystem. What
//  is worth pinning here is not the formatting — `CSVWriter` owns that — but the shape: every row
//  the same width as its header, ids present so the files can be joined back together, and nothing
//  silently dropped because a field happened to be nil.
//
//  These files are somebody's record of a relationship, quite possibly read years later, after the
//  archive itself has been deleted. So they lean towards writing more rather than less, and towards
//  columns whose meaning is obvious without the app that made them.
//

import Foundation

enum CoupleDataTables {

    // MARK: - Trips

    static let tripHeader = [
        "trip_id", "category", "origin_city", "origin_country", "origin_iata",
        "destination_city", "destination_country", "destination_iata",
        "departure", "arrival", "distance_km", "travellers", "linked_flight_ids", "notes",
    ]

    static func tripRow(_ trip: Trip, nameFor: (UUID) -> String) -> [String] {
        [
            trip.id.uuidString,
            trip.category.rawValue,
            trip.origin.city,
            trip.origin.country,
            trip.origin.iataCode ?? "",
            trip.destination.city,
            trip.destination.country,
            trip.destination.iataCode ?? "",
            CSVWriter.timestamp(trip.departureDate),
            CSVWriter.timestamp(trip.arrivalDate),
            // The effective distance, which follows the actual flown legs where there are any —
            // the same number the app shows, rather than the great-circle line between endpoints.
            CSVWriter.number(trip.effectiveDistanceKm),
            trip.travelerIDs.map(nameFor).joined(separator: "; "),
            trip.flights.map(\.id.uuidString).joined(separator: "; "),
            trip.notes ?? "",
        ]
    }

    // MARK: - Memories

    static let memoryHeader = [
        "memory_id", "title", "date", "city", "country", "latitude", "longitude",
        "trip_id", "photo_count", "photo_files", "note",
    ]

    /// `photoFiles` are the names this memory's photos are given inside the export's `media/`
    /// folder, so the CSV and the images can be matched up by hand. Built by the exporter, which
    /// is what actually writes them, rather than derived here from a storage path that means
    /// nothing outside the app.
    static func memoryRow(_ memory: Memory, photoFiles: [String]) -> [String] {
        [
            memory.id.uuidString,
            memory.title,
            CSVWriter.day(memory.date),
            memory.place?.city ?? "",
            memory.place?.country ?? "",
            memory.place.map { CSVWriter.number($0.latitude, decimals: 6) } ?? "",
            memory.place.map { CSVWriter.number($0.longitude, decimals: 6) } ?? "",
            memory.tripID?.uuidString ?? "",
            String(memory.photos.count),
            photoFiles.joined(separator: "; "),
            memory.note,
        ]
    }

    // MARK: - Flights

    static let flightHeader = [
        "flight_id", "flight_number", "airline", "aircraft",
        "origin_iata", "origin_city", "origin_timezone",
        "destination_iata", "destination_city", "destination_timezone",
        "scheduled_departure", "actual_departure", "scheduled_arrival", "actual_arrival",
        "departure_delay_minutes", "arrival_delay_minutes",
        "status", "cancelled", "diverted", "trip_id", "travellers",
    ]

    static func flightRow(_ flight: Flight, nameFor: (UUID) -> String) -> [String] {
        [
            flight.id.uuidString,
            // What was on the boarding pass wins over the operating number, the same rule the app
            // displays by — someone reading this back recognises the one they flew under.
            flight.marketingFlightNumber ?? flight.flightNumberIATA,
            flight.airlineName ?? flight.airlineCode ?? "",
            flight.aircraftType ?? "",
            flight.origin.iata ?? flight.origin.icao ?? "",
            flight.origin.city ?? flight.origin.name ?? "",
            flight.origin.timezone ?? "",
            flight.destination.iata ?? flight.destination.icao ?? "",
            flight.destination.city ?? flight.destination.name ?? "",
            flight.destination.timezone ?? "",
            CSVWriter.timestamp(flight.scheduledOut),
            CSVWriter.timestamp(flight.actualOut),
            CSVWriter.timestamp(flight.scheduledIn),
            CSVWriter.timestamp(flight.actualIn),
            minutes(flight.departureDelaySeconds),
            minutes(flight.arrivalDelaySeconds),
            flight.status.rawValue,
            CSVWriter.flag(flight.cancelled),
            CSVWriter.flag(flight.diverted),
            flight.tripID?.uuidString ?? "",
            flight.travelerIDs.map(nameFor).joined(separator: "; "),
        ]
    }

    /// Delays in minutes, not seconds. Nobody reads a delay in seconds, and the provider's own
    /// precision is a minute anyway. Negative means early, which is real information and is kept.
    private static func minutes(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        return String(seconds / 60)
    }

    // MARK: - Games

    static let gameHeader = [
        "session_id", "game", "deck", "played_on", "status", "rounds_completed", "rounds_total",
    ]

    static func gameRow(_ session: ExportedGameSession) -> [String] {
        [
            session.id.uuidString,
            session.gameType,
            session.deckTitle ?? "",
            CSVWriter.timestamp(session.startedAt),
            session.status,
            String(session.roundsCompleted),
            String(session.roundsTotal),
        ]
    }
}

/// A game session as the export needs it.
///
/// Its own type rather than the app's `GameSession`, because an export can be of a *dissolved*
/// couple whose sessions are not in `AppModel` at all — they are fetched by `couple_id` and only
/// these fields are needed. Keeping it separate also means a change to the in-app game model
/// cannot silently change the columns of a file someone already has on disk.
struct ExportedGameSession: Identifiable, Decodable {
    let id: UUID
    var gameType: String
    var deckTitle: String?
    var startedAt: Date?
    var status: String
    var roundsCompleted: Int
    var roundsTotal: Int
}
