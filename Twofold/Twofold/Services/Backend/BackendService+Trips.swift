//
//  BackendService+Trips.swift
//  Twofold
//
//  Trips: rows, inserts, edits and deletes.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Trips / flights

    struct TripRow: Decodable {
        var id: UUID
        var travelerIds: [UUID]
        var originId: UUID
        var destinationId: UUID
        var departureAt: Date
        var arrivalAt: Date
        var category: TripCategory
        var distanceKm: Double
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case id, category, notes
            case travelerIds = "traveler_ids"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    private struct TripInsert: Encodable {
        var id: UUID
        var coupleId: UUID
        var travelerIds: [UUID]
        var originId: UUID
        var destinationId: UUID
        var departureAt: Date
        var arrivalAt: Date
        var category: TripCategory
        var distanceKm: Double

        enum CodingKeys: String, CodingKey {
            case id, category
            case coupleId = "couple_id"
            case travelerIds = "traveler_ids"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    /// Couple-scoped re-fetch (mirrors `fetchFlights(coupleID:)`/`fetchMemories(coupleID:)`) —
    /// trips had the same gap memories did: only ever bulk-populated once via
    /// `fetchCoupleState()`'s adopt, so a partner's newly-added trip never appeared short of a
    /// full relaunch. Flight linkage isn't resolved here — `AppModel.refreshTrips()` links each
    /// trip to `self.flights` itself (and `refreshFlights()`, called alongside it, re-links
    /// authoritatively from the fetched flight rows either way).
    static func fetchTrips(coupleID: UUID) async throws -> [Trip] {
        let tripRows: [TripRow] = try await supabase
            .from("trips")
            .select()
            .eq("couple_id", value: coupleID)
            .execute()
            .value

        var placeIDs = Set<UUID>()
        for row in tripRows { placeIDs.insert(row.originId); placeIDs.insert(row.destinationId) }
        let places = try await fetchPlaces(ids: Array(placeIDs))

        return tripRows.compactMap { row in
            guard let origin = places[row.originId], let destination = places[row.destinationId] else { return nil }
            return Trip(
                id: row.id,
                travelerIDs: row.travelerIds,
                origin: origin,
                destination: destination,
                departureDate: row.departureAt,
                arrivalDate: row.arrivalAt,
                category: row.category,
                distanceKm: row.distanceKm,
                notes: row.notes
            )
        }
    }

    /// Explicit for the same reason as `TripIDUpdate`: clearing a trip's notes passes nil, and
    /// synthesised encoding would drop the key and leave the old note in place.
    private struct TripNotesUpdate: Encodable {
        var notes: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(notes, forKey: .notes)
        }

        enum CodingKeys: String, CodingKey { case notes }
    }

    static func updateTripNotes(tripID: UUID, notes: String?) async throws {
        try await supabase
            .from("trips")
            .update(TripNotesUpdate(notes: notes))
            .eq("id", value: tripID)
            .execute()
    }

    /// Inserts a trip using the client-generated id already on `trip`, resolving origin/
    /// destination against the `places` table. Never writes a flight — flights are only ever
    /// written by the `add-flight`/`refresh-flight` Edge Functions (service role key) once a
    /// real AeroAPI candidate is resolved via `AeroFlightService.addFlight`, called separately
    /// once the trip this returns exists.
    static func insertTrip(coupleID: UUID, trip: Trip) async throws {
        let originID = try await findOrCreatePlaceID(trip.origin)
        let destinationID = try await findOrCreatePlaceID(trip.destination)

        try await supabase
            .from("trips")
            .insert(
                TripInsert(
                    id: trip.id,
                    coupleId: coupleID,
                    travelerIds: trip.travelerIDs,
                    originId: originID,
                    destinationId: destinationID,
                    departureAt: trip.departureDate,
                    arrivalAt: trip.arrivalDate,
                    category: trip.category,
                    distanceKm: trip.distanceKm
                )
            )
            .execute()
    }

    /// Only the columns a `TripEdit` changed. Hand-written so an absent field is left out of the
    /// PATCH entirely — PostgREST leaves an omitted column alone — while notes cleared on purpose
    /// still write a null.
    private struct TripUpdate: Encodable {
        var travelerIds: [UUID]?
        var originId: UUID?
        var destinationId: UUID?
        var departureAt: Date?
        var arrivalAt: Date?
        var category: TripCategory?
        var distanceKm: Double?
        var notes: Changed<String?>?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(travelerIds, forKey: .travelerIds)
            try container.encodeIfPresent(originId, forKey: .originId)
            try container.encodeIfPresent(destinationId, forKey: .destinationId)
            try container.encodeIfPresent(departureAt, forKey: .departureAt)
            try container.encodeIfPresent(arrivalAt, forKey: .arrivalAt)
            try container.encodeIfPresent(category, forKey: .category)
            try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
            if let notes { try container.encode(notes.value, forKey: .notes) }
        }

        enum CodingKeys: String, CodingKey {
            case category, notes
            case travelerIds = "traveler_ids"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    /// The fields of a trip somebody changed, and only those (`TripEdit`) — as opposed to
    /// `updateTripNotes` (notes only). A changed city is resolved against `places` fresh, same as
    /// `insertTrip`.
    static func updateTrip(_ edit: TripEdit) async throws {
        let rows: [TripRow]
        var originID: UUID?
        var destinationID: UUID?
        if let origin = edit.origin { originID = try await findOrCreatePlaceID(origin) }
        if let destination = edit.destination { destinationID = try await findOrCreatePlaceID(destination) }
        rows = try await supabase
            .from("trips")
            .update(
                TripUpdate(
                    travelerIds: edit.travelerIDs,
                    originId: originID,
                    destinationId: destinationID,
                    departureAt: edit.departureDate,
                    arrivalAt: edit.arrivalDate,
                    category: edit.category,
                    distanceKm: edit.distanceKm,
                    notes: edit.notes
                )
            )
            .eq("id", value: edit.tripID)
            // See `updateMemory` — without `.select()` a refused update looks like a saved one.
            .select()
            .execute()
            .value as [TripRow]
        guard !rows.isEmpty else { throw WriteAffectedNoRows() }
    }

    /// `flights.trip_id`/`memories.trip_id` both have `on delete set null`, so any linked
    /// flight or memory survives untethered rather than disappearing along with the trip.
    static func deleteTrip(id: UUID) async throws {
        // Only the documents attached to the trip itself. Its flights survive the delete
        // (`flights.trip_id` is `on delete set null`, so they're unlinked rather than removed) and
        // keep their own attachments.
        let documentPaths = await flightDocumentPaths(tripID: id)
        try await supabase.from("trips").delete().eq("id", value: id).execute()
        await removeFlightDocumentObjects(documentPaths)
    }

    /// Encodes explicitly, so `nil` becomes `"trip_id": null` rather than being left out.
    ///
    /// Swift's *synthesised* `Encodable` uses `encodeIfPresent` for an optional, which omits the
    /// key entirely — so `TripIDUpdate(tripId: nil)` encoded to `{}`, PostgREST received a PATCH
    /// with nothing in it, and unlinking a flight changed nothing on the server. It looked like it
    /// worked because the local edit is applied optimistically; the flight reappeared on the trip
    /// at the next full refresh, which is whenever anything else was added.
    ///
    /// `container.encode` rather than `encodeIfPresent` is the whole difference: `Optional`
    /// conforms to `Encodable` and writes a null.
    ///
    /// (The distinction is whether `nil` means "clear this" or "leave this alone", and it has to be
    /// decided per payload rather than inherited from the synthesis. `SubscriptionStatusUpdate`
    /// used to be the counter-example here, deliberately omitting a nil tier; it is gone with the
    /// client-side subscription write.)
    struct TripIDUpdate: Encodable {
        var tripId: UUID?
        enum CodingKeys: String, CodingKey { case tripId = "trip_id" }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tripId, forKey: .tripId)
        }
    }

    #if DEBUG
    /// Test seams for the update payloads whose optional encoding decides whether a column is
    /// cleared or left alone. The structs are private and the distinction is invisible at the type
    /// level, so `UpdatePayloadEncodingTests` reads the bytes these produce.
    static func tripIDUpdateForTesting(tripID: UUID?) -> some Encodable { TripIDUpdate(tripId: tripID) }
    static func tripNotesUpdateForTesting(notes: String?) -> some Encodable { TripNotesUpdate(notes: notes) }
    static func tripUpdateForTesting(category: TripCategory?, notes: Changed<String?>?) -> some Encodable {
        TripUpdate(category: category, notes: notes)
    }
    #endif
}
