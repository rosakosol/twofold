//
//  RemoteImageDiskCacheTests.swift
//  TwofoldTests
//
//  The two properties this cache exists for, both of which it got wrong.
//
//  It is read on a cold launch with no network, when the bytes on disk are the only copy of an
//  avatar or a drawing there will be. That makes the key the whole design: it has to survive a
//  relaunch, and it has to survive the URL being re-signed.
//

import Testing
import Foundation
import UIKit
@testable import Twofold

@Suite(.serialized)
struct RemoteImageDiskCacheTests {

    /// A real signed Storage URL: same object, two signings, different token and expiry.
    private let firstSigning = URL(string: "https://x.supabase.co/storage/v1/object/sign/drawing-pads/couple/person/pad.png?token=aaa&exp=1")!
    private let secondSigning = URL(string: "https://x.supabase.co/storage/v1/object/sign/drawing-pads/couple/person/pad.png?token=bbb&exp=2")!

    private func pngBytes() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
    }

    /// The reason a full-URL key (URLSession's own cache, `AsyncImage`) is useless here: the token
    /// changes on every re-sign, so it misses even for an image downloaded seconds earlier.
    @Test("an image stored under one signing is found under the next")
    func keyIgnoresTheSignature() {
        RemoteImageDiskCache.clear()
        RemoteImageDiskCache.store(pngBytes(), for: firstSigning)
        #expect(RemoteImageDiskCache.image(for: secondSigning) != nil, "re-signing must not lose the image")
        RemoteImageDiskCache.clear()
    }

    /// The bug this file was written for. `hashValue` seeds its hasher randomly per process, so the
    /// filename changed on every launch and the cache never hit on the one launch that needed it.
    /// A hash that isn't stable across processes fails here, because a fixed digest can't match it.
    @Test("the filename is stable across processes, not just within one")
    func keyIsStableAcrossLaunches() throws {
        RemoteImageDiskCache.clear()
        RemoteImageDiskCache.store(pngBytes(), for: firstSigning)

        let directory = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("RemoteImages", isDirectory: true)
        )
        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        // SHA256 of the URL's path — computed here rather than read back from the cache, so this
        // pins the name to something a *future* process can also arrive at.
        #expect(written == ["892386efeff4a1c714933b18997cdfac04172eeffbba91dc78dcabd07f4b7b87.img"])
        RemoteImageDiskCache.clear()
    }

    /// Two different images must not collide on one file — the couple would see one face twice.
    @Test("different images keep different files")
    func distinctPathsDoNotCollide() {
        RemoteImageDiskCache.clear()
        let mine = URL(string: "https://x.supabase.co/storage/v1/object/sign/avatars/couple/me/avatar.jpg?token=a")!
        let theirs = URL(string: "https://x.supabase.co/storage/v1/object/sign/avatars/couple/them/avatar.jpg?token=a")!
        RemoteImageDiskCache.store(pngBytes(), for: mine)
        #expect(RemoteImageDiskCache.image(for: theirs) == nil)
        RemoteImageDiskCache.clear()
    }

    /// Signing out has to take the partner's face with it.
    @Test("clearing removes what was stored")
    func clearingEmptiesTheCache() {
        RemoteImageDiskCache.store(pngBytes(), for: firstSigning)
        RemoteImageDiskCache.clear()
        #expect(RemoteImageDiskCache.image(for: firstSigning) == nil)
    }
}
