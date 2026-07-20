//
//  PendingTripStore.swift
//  Twofold
//
//  Local disk persistence for trips added before pairing with a partner (or that otherwise
//  failed to sync) — mirrors `PendingMemoryStore`, which already did this for memories. AppModel
//  itself is pure in-memory, so without this a pending trip was lost the moment the app was
//  killed, even though the whole point of allowing trips before pairing is "add it now, it syncs
//  once your partner joins." A pending trip never has a `Flight` attached directly (see
//  `AppModel.pendingFlightCandidates` for how a picked flight is tracked separately until the
//  trip exists server-side), so the on-disk snapshot below omits it rather than requiring
//  `Flight` to be `Codable` just for this.
//

import Foundation

enum PendingTripStore {
    private struct Manifest: Codable {
        var id: UUID
        var travelerIDs: [Person.ID]
        var origin: Place
        var destination: Place
        var departureDate: Date
        var arrivalDate: Date
        var isReunionTrip: Bool
        var distanceKm: Double
        var notes: String?

        init(trip: Trip) {
            id = trip.id
            travelerIDs = trip.travelerIDs
            origin = trip.origin
            destination = trip.destination
            departureDate = trip.departureDate
            arrivalDate = trip.arrivalDate
            isReunionTrip = trip.isReunionTrip
            distanceKm = trip.distanceKm
            notes = trip.notes
        }

        var trip: Trip {
            Trip(
                id: id,
                travelerIDs: travelerIDs,
                origin: origin,
                destination: destination,
                departureDate: departureDate,
                arrivalDate: arrivalDate,
                isReunionTrip: isReunionTrip,
                distanceKm: distanceKm,
                notes: notes
            )
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingTrips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func manifestURL(for id: Trip.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Persists (or re-persists, if `notes` changed) a trip that isn't synced yet.
    static func save(_ trip: Trip) {
        guard let data = try? JSONEncoder().encode(Manifest(trip: trip)) else { return }
        try? data.write(to: manifestURL(for: trip.id), options: .atomic)
    }

    /// Every trip still waiting to sync.
    static func loadAll() -> [Trip] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
            return manifest.trip
        }
    }

    /// Called once a pending trip successfully syncs to the backend, or is deleted locally
    /// before ever syncing.
    static func remove(id: Trip.ID) {
        try? FileManager.default.removeItem(at: manifestURL(for: id))
    }
}
