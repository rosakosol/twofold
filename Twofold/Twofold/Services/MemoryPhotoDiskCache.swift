//
//  MemoryPhotoDiskCache.swift
//  Twofold
//
//  On-disk copies of memory photos, so a couple can actually browse their memories on a plane.
//
//  `MemoryPhotoImageCache` (in MemoryPhotoView) is an `NSCache` — in-memory only, so it's empty on
//  every cold launch, which is exactly the state someone opening the app mid-flight is in. And the
//  photos can't be re-fetched then either: `memory-photos` is a private bucket, so `MemoryPhoto.url`
//  is a *signed* URL that both expires and is re-issued differently on every `fetchCoupleState()`,
//  which is also why URLSession's own cache never gets a hit on them.
//
//  Keyed on the photo's stable storage `path` for the same reason `MemoryPhotoImageCache` is: the
//  signed URL changes on every load, the path doesn't. Hashed because a real path
//  ("{coupleID}/{memoryID}/{uuid}.jpg") contains separators that can't go in a filename.
//
//  Bounded, because a couple with a long history can have hundreds of photos and this is otherwise
//  unbounded growth on the user's device. Eviction is least-recently-used, driven by the files'
//  own modification dates, which `touch(_:)` refreshes on every read.
//

import CryptoKit
import Foundation

enum MemoryPhotoDiskCache {
    /// Generous enough to hold a typical couple's whole history (photos are downscaled to 1600px
    /// and JPEG-compressed on upload — see `AddMemoryView.loadNewPhotos` — so a few hundred KB
    /// each), while still bounding what this can ever consume.
    private static let maxBytes: Int = 250 * 1024 * 1024

    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MemoryPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func filename(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    static func fileURL(for path: String) -> URL {
        directory.appendingPathComponent(filename(for: path))
    }

    static func has(path: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: path).path)
    }

    static func read(path: String) -> Data? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    static func write(_ data: Data, path: String) {
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    /// Marks a file as just-used so eviction sheds genuinely cold photos rather than whichever
    /// happened to be downloaded first.
    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// Drops least-recently-used files until the directory is back under `maxBytes`. Called after
    /// a prefetch pass rather than on every write, so a browsing session doesn't pay for it.
    static func enforceSizeLimit() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let entries: [(url: URL, size: Int, modified: Date)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }

        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxBytes else { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Cleared on sign-out alongside every other local trace of the account — these are the
    /// couple's private photos and must not outlive their session on a shared device.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
