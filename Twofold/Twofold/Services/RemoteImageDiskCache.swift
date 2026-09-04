//
//  RemoteImageDiskCache.swift
//  Twofold
//
//  On-disk copies of the small remote images the app draws everywhere — avatars and drawing pads.
//
//  Both were cached in an `NSCache`, which is memory-only and therefore empty on every cold launch.
//  Online that's invisible: they redownload in a moment. Offline it meant a cold start showed
//  initials where two faces should be, and two blank rectangles where the couple's drawings were —
//  on the launch where there is nothing else to look at.
//
//  Keyed on the URL's *path*, not the whole URL, for the reason `AvatarView`'s own cache already
//  documents: these are signed Storage URLs whose token and expiry change on every re-sign, so the
//  full string is never the same twice and a cache keyed on it never hits. The storage path is
//  stable across re-signs, and is the real identity of the image.
//
//  Deliberately separate from `MemoryPhotoDiskCache`: that one is bounded for hundreds of
//  full-size photos and evicts accordingly. This holds a handful of small images that must survive
//  as long as the account does, so evicting them on size would defeat the point.
//

import CryptoKit
import Foundation
import UIKit

enum RemoteImageDiskCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Hashed because a real storage path ("{coupleID}/{personID}/avatar.jpg") contains separators
    /// that can't go in a filename — SHA256, the same as `MemoryPhotoDiskCache`.
    ///
    /// Not `hashValue`: Swift seeds its hasher randomly per process, so the same path produces a
    /// different filename on every launch. A cache whose key doesn't survive a relaunch is no cache
    /// at all here, since a cold launch is the only time this is the last copy of the image.
    private static func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    static func image(for url: URL) -> UIImage? {
        let file = directory.appendingPathComponent(filename(for: url))
        guard let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    static func store(_ data: Data, for url: URL) {
        // Written as the original bytes rather than a re-encoded UIImage: re-encoding costs quality
        // and time for no benefit, and these are already small.
        try? data.write(to: directory.appendingPathComponent(filename(for: url)), options: .atomic)
    }

    /// Cleared on sign-out and account deletion, alongside every other local trace of the account —
    /// the next person on this device must not inherit a partner's face.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
