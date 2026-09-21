//
//  PendingMemoryStore.swift
//  Twofold
//
//  Local disk persistence for memories added before pairing with a partner (or that otherwise
//  failed to sync). AppModel itself is pure in-memory — without this, a pending memory and its
//  photos were lost the moment the app was killed, even though the whole point of allowing
//  memories before pairing is "add it now, it links to your partner once they join." Also gives
//  a pending memory real local `file://` URLs for its photos, so `MemoryPhotoView` (which only
//  ever reads `Memory.photos[].url`) renders them immediately with no changes of its own.
//

import Foundation

enum PendingMemoryStore {
    private struct Manifest: Codable {
        var memory: Memory
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingMemories", isDirectory: true)
        // The directory carries a class of its own, and it is what a file created inside it
        // without one inherits — so this is what catches a future writer that forgets the option.
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return dir
    }

    private static func manifestURL(for id: Memory.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func photoURL(memoryID: Memory.ID, index: Int) -> URL {
        directory.appendingPathComponent("\(memoryID.uuidString)-\(index).jpg")
    }

    /// Writes photo bytes to local files, attaches `MemoryPhoto` entries pointing at them, and
    /// persists the memory to disk — one call covers both "show the photo right now" and
    /// "survive a relaunch." Returns the memory with its local-URL photos attached, ready to
    /// append straight into `AppModel.memories`.
    @discardableResult
    /// Everything drafted but not yet synced, including the photo files.
    ///
    /// Same reasoning as `PendingTripStore.clear()`, and more to lose: a drafted memory carries
    /// its photo bytes, so the next account on the device inherited the previous one's pictures
    /// and uploaded them into its own couple's archive on pairing.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func save(memory: Memory, photosData: [Data]) -> Memory {
        var memory = memory
        var photos: [MemoryPhoto] = []
        for (index, data) in photosData.enumerated() {
            let url = photoURL(memoryID: memory.id, index: index)
            guard (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil else { continue }
            photos.append(MemoryPhoto(id: UUID(), path: "pending", url: url))
        }
        memory.photos = photos

        if let data = try? JSONEncoder().encode(Manifest(memory: memory)) {
            try? data.write(to: manifestURL(for: memory.id), options: [.atomic, .completeFileProtection])
        }
        return memory
    }

    /// Every memory still waiting to sync, with its local photo bytes re-read from disk (needed
    /// to re-populate `AppModel.pendingMemoryPhotoData` so the eventual upload still has the
    /// raw bytes to send).
    static func loadAll() -> [(memory: Memory, photosData: [Data])] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var results: [(memory: Memory, photosData: [Data])] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { continue }

            // Each photo's URL is rebuilt from *this* install's directory rather than read back
            // out of the manifest.
            //
            // The manifest stores whatever absolute URL `save` produced, and an app container's
            // path contains a UUID that changes when the app is reinstalled or updated. So a
            // memory drafted before an update came back with photo URLs pointing at a directory
            // that no longer exists: `Data(contentsOf:)` failed for every one of them, `loadAll`
            // returned the memory with an empty `photosData`, and the upload that runs when the
            // couple forms sent no photos at all. The memory survived the update; its pictures did
            // not.
            //
            // The filenames are deterministic — `photoURL(memoryID:index:)` — so the position in
            // the manifest is all that is needed to find them again.
            var memory = manifest.memory
            var photos: [MemoryPhoto] = []
            var photosData: [Data] = []
            for (index, photo) in memory.photos.enumerated() {
                let url = photoURL(memoryID: memory.id, index: index)
                guard let data = try? Data(contentsOf: url) else { continue }
                // Rewritten as well as read, so the copy handed to the UI points at a file that is
                // actually there and the thumbnail draws.
                photos.append(MemoryPhoto(id: photo.id, path: "pending", url: url))
                photosData.append(data)
            }
            memory.photos = photos

            results.append((memory, photosData))
        }
        return results
    }

    /// Called once a pending memory successfully syncs to the backend, or is deleted locally
    /// before ever syncing — removes its manifest and any locally-cached photo files.
    static func remove(id: Memory.ID) {
        try? FileManager.default.removeItem(at: manifestURL(for: id))
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(id.uuidString)-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
