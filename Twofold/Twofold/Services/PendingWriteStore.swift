//
//  PendingWriteStore.swift
//  Twofold
//
//  The outbox: every edit AppModel makes to a trip, memory, flight link or profile field is
//  written here before it is sent, and taken out once the server has it. AppModel replays what is
//  left at launch, on returning to the foreground and on reconnecting (`syncPendingWrites`), and
//  re-applies it on top of every refresh, so a refresh that lands before an edit has been sent
//  shows the edit rather than the server's older copy.
//
//  Creating a trip or memory is not in here: those already have their own durable copy in
//  `PendingTripStore`/`PendingMemoryStore`, and an edit to something not created yet is folded
//  into that copy. An entry that refers to a trip or memory still waiting to be created waits for
//  it (see `AppModel.isReadyToSend`).
//
//  Main-app only, a file under Application Support at Complete protection — the same choices as
//  `PendingGameResponseStore` and for the same reason: these are the couple's own words.
//

import Foundation

enum PendingWrite: Codable, Hashable {
    /// The fields of a trip somebody changed (`TripEdit`), and only those.
    case tripEdit(TripEdit)
    /// Every field of a trip except its flights. Only ever read back from a queue an older build
    /// wrote, before edits carried just the changed fields; nothing queues one now.
    case trip(Trip)
    case tripNotes(tripID: UUID, notes: String?)
    case flightTrip(flightID: UUID, tripID: UUID?)
    case flightTravelers(flightID: UUID, travelerIDs: [UUID])
    /// The fields of a memory somebody changed (`MemoryEdit`), and only those. Photos travel
    /// separately.
    case memoryEdit(MemoryEdit)
    /// Title, place, date and note in full. Like `trip`, only read back from an older build's queue.
    case memory(Memory)
    case memoryTrip(memoryID: UUID, tripID: UUID?)
    /// Photos added to a memory that already exists on the server. The bytes are files beside
    /// the queue, named by photo id; each `MemoryPhoto` here is the local stand-in shown meanwhile.
    case memoryPhotos(memoryID: UUID, photos: [MemoryPhoto])
    case removeMemoryPhoto(memoryID: UUID, photoID: UUID, path: String)
    case firstName(String)
    case partnerNickname(String)
    case partnerHomeCity(Place)
    case homeCity(Place)
    case anniversaryDate(Date)

    /// Whether this writes to the trip, memory or flight with this id.
    func targets(_ id: UUID) -> Bool {
        switch self {
        case .tripEdit(let edit): edit.tripID == id
        case .trip(let trip): trip.id == id
        case .tripNotes(let tripID, _): tripID == id
        case .flightTrip(let flightID, _), .flightTravelers(let flightID, _): flightID == id
        case .memoryEdit(let edit): edit.memoryID == id
        case .memory(let memory): memory.id == id
        case .memoryTrip(let memoryID, _), .memoryPhotos(let memoryID, _), .removeMemoryPhoto(let memoryID, _, _): memoryID == id
        case .firstName, .partnerNickname, .partnerHomeCity, .homeCity, .anniversaryDate: false
        }
    }

    /// Two writes with the same key set the same thing, so only the newer one needs sending —
    /// merged onto the older first where each may set different fields (`merged(onto:)`).
    /// Nil for writes that add something and must each be sent.
    var coalescingKey: String? {
        switch self {
        case .tripEdit(let edit): "tripEdit:\(edit.tripID)"
        case .trip(let trip): "trip:\(trip.id)"
        case .tripNotes(let id, _): "tripNotes:\(id)"
        case .flightTrip(let id, _): "flightTrip:\(id)"
        case .flightTravelers(let id, _): "flightTravelers:\(id)"
        case .memoryEdit(let edit): "memoryEdit:\(edit.memoryID)"
        case .memory(let memory): "memory:\(memory.id)"
        case .memoryTrip(let id, _): "memoryTrip:\(id)"
        case .memoryPhotos: nil
        case .removeMemoryPhoto(_, let photoID, _): "removeMemoryPhoto:\(photoID)"
        case .firstName: "firstName"
        case .partnerNickname: "partnerNickname"
        case .partnerHomeCity: "partnerHomeCity"
        case .homeCity: "homeCity"
        case .anniversaryDate: "anniversaryDate"
        }
    }

    /// This write in place of `older`, which has the same `coalescingKey` and has not been sent.
    /// An edit to the title queued after one to the date has to carry the date too, or replacing
    /// the older entry would lose it.
    func merged(onto older: PendingWrite) -> PendingWrite {
        switch (self, older) {
        case let (.tripEdit(newer), .tripEdit(older)): .tripEdit(newer.merged(onto: older))
        case let (.memoryEdit(newer), .memoryEdit(older)): .memoryEdit(newer.merged(onto: older))
        default: self
        }
    }
}

struct PendingWriteEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var write: PendingWrite
    let queuedAt: Date
}

enum PendingWriteStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingWrites", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return dir
    }

    private static var queueURL: URL { directory.appendingPathComponent("queue.json") }

    /// Where a queued photo's bytes live. Rebuilt from the id on every read rather than trusting
    /// the URL stored in the queue, because the app container's path changes on reinstall and
    /// update — the same trap `PendingMemoryStore.loadAll` describes.
    static func photoURL(id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Oldest first.
    static func all() -> [PendingWriteEntry] {
        guard let data = try? Data(contentsOf: queueURL),
              let entries = try? JSONDecoder().decode([PendingWriteEntry].self, from: data) else { return [] }
        return entries.map { entry in
            guard case let .memoryPhotos(memoryID, photos) = entry.write else { return entry }
            var entry = entry
            entry.write = .memoryPhotos(
                memoryID: memoryID,
                photos: photos.map { MemoryPhoto(id: $0.id, path: $0.path, url: photoURL(id: $0.id)) }
            )
            return entry
        }
    }

    /// Queues `write` at the back, replacing any older write to the same thing.
    @discardableResult
    static func add(_ write: PendingWrite) -> PendingWriteEntry {
        var entries = all()
        var write = write
        if let key = write.coalescingKey {
            if let older = entries.last(where: { $0.write.coalescingKey == key }) {
                write = write.merged(onto: older.write)
            }
            entries.removeAll { $0.write.coalescingKey == key }
        }
        let entry = PendingWriteEntry(id: UUID(), write: write, queuedAt: .now)
        entries.append(entry)
        save(entries)
        return entry
    }

    /// Takes an entry out once it has been sent (or refused), with any photo files it carried.
    static func remove(id: UUID) {
        var entries = all()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let removed = entries.remove(at: index)
        if case let .memoryPhotos(_, photos) = removed.write {
            for photo in photos { try? FileManager.default.removeItem(at: photoURL(id: photo.id)) }
        }
        save(entries)
    }

    /// Everything queued for a trip, memory or flight that has just been deleted. Sent afterwards,
    /// each would find no row and come back as a refusal.
    static func removeAll(targeting id: UUID) {
        for entry in all() where entry.write.targets(id) {
            remove(id: entry.id)
        }
    }

    /// Writes a photo's bytes beside the queue and returns the stand-in to show until it uploads.
    static func savePhoto(_ data: Data) -> MemoryPhoto? {
        let id = UUID()
        let url = photoURL(id: id)
        guard (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        return MemoryPhoto(id: id, path: MemoryPhoto.pendingPath, url: url)
    }

    static func photoData(id: UUID) -> Data? {
        try? Data(contentsOf: photoURL(id: id))
    }

    /// A queued photo removed before it was ever uploaded: nothing to tell the server, it just
    /// leaves the queue.
    static func removeQueuedPhoto(id: UUID) {
        var entries = all()
        for index in entries.indices {
            guard case let .memoryPhotos(memoryID, photos) = entries[index].write,
                  photos.contains(where: { $0.id == id }) else { continue }
            entries[index].write = .memoryPhotos(memoryID: memoryID, photos: photos.filter { $0.id != id })
        }
        entries.removeAll {
            if case let .memoryPhotos(_, photos) = $0.write { return photos.isEmpty }
            return false
        }
        try? FileManager.default.removeItem(at: photoURL(id: id))
        save(entries)
    }

    /// Signing out takes the queue with it. Every write here goes out as whoever is signed in
    /// when it is sent, so one left behind would be applied to the next account on the device.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func save(_ entries: [PendingWriteEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: queueURL, options: [.atomic, .completeFileProtection])
    }
}

extension MemoryPhoto {
    /// The `path` of a photo that exists only on this device so far — drafted into a memory not
    /// yet created (`PendingMemoryStore`), or added offline to one that is (`PendingWriteStore`).
    static let pendingPath = "pending"

    var isPending: Bool { path == Self.pendingPath }
}
