//
//  R2StorageTests.swift
//  TwofoldTests
//
//  The client half of the move off Supabase Storage.
//
//  The server half is thoroughly covered — eight signing tests against botocore, a live round trip
//  against the bucket, thirty-one pgTAP cases on `can_access_storage_object`. None of that says
//  anything about this side, which was verified only by "the app rendered an avatar once".
//
//  Two things here are worth pinning, and both fail quietly rather than loudly.
//
//  The chunk size is shared with `storage-url`'s `MAX_PATHS` and enforced only there. If they drift,
//  nothing crashes: every oversized batch 400s, `memoryPhotoSignedURLs` falls back to its per-path
//  retry, and a memories grid costs 600 round trips instead of 6 — slower, not broken, so nobody
//  reports it. (`storage-url/index.test.ts` pins the same number from the other end.)
//
//  The `Kind` raw values are the wire contract. A typo produces "Unknown 'kind'" and a screen of
//  missing images, with the compiler perfectly happy either way.
//

import Testing
import Foundation
@testable import Twofold

struct R2StorageTests {

    // MARK: - The wire contract

    /// Exactly the four keys `storage-url`'s PREFIX map holds. Not a restatement of the enum: these
    /// are the strings the server matches on, written out independently so that renaming a case
    /// cannot silently rename what goes over the wire.
    @Test("kind raw values match what the server accepts")
    func kindsMatchServer() {
        #expect(R2Storage.Kind.avatar.rawValue == "avatar")
        #expect(R2Storage.Kind.drawingPad.rawValue == "drawing-pad")
        #expect(R2Storage.Kind.memoryPhoto.rawValue == "memory-photo")
        #expect(R2Storage.Kind.flightDocument.rawValue == "flight-document")
    }

    // MARK: - Chunking

    @Test("the chunk size matches the server's MAX_PATHS")
    func chunkSizeMatchesServer() {
        #expect(R2Storage.maxPathsPerRequest == 100)
    }

    /// The case this exists for. A couple with 200 memories averaging three photos is 600 paths, and
    /// one request of 600 comes back 400 with nothing in it.
    @Test("a realistic library is split into request-sized batches")
    func splitsALargeLibrary() {
        let paths = (0 ..< 600).map { "couple/memory/\($0).jpg" }
        let chunks = R2Storage.chunked(paths)

        #expect(chunks.count == 6)
        #expect(chunks.allSatisfy { $0.count <= R2Storage.maxPathsPerRequest })
        #expect(chunks.flatMap { $0 } == paths, "chunking reordered or dropped paths")
    }

    /// Boundaries, because an off-by-one here is a 101st path that silently 400s the whole batch it
    /// travels in.
    @Test("boundaries are exact", arguments: [
        (0, 0), (1, 1), (99, 1), (100, 1), (101, 2), (200, 2), (201, 3),
    ])
    func boundaries(count: Int, expectedChunks: Int) {
        let paths = (0 ..< count).map { "p/\($0)" }
        let chunks = R2Storage.chunked(paths)
        #expect(chunks.count == expectedChunks)
        #expect(chunks.reduce(0) { $0 + $1.count } == count)
        #expect(chunks.allSatisfy { !$0.isEmpty }, "an empty chunk would be a request asking for nothing")
    }

    /// Nothing is lost or duplicated, whatever the size. `readURLs` merges the chunks back into one
    /// dictionary keyed by path, so a dropped path is a photo that never appears and a duplicated
    /// one is a wasted request.
    @Test("every path survives exactly once", arguments: [1, 7, 100, 101, 250, 999])
    func losesNothing(count: Int) {
        let paths = (0 ..< count).map { "couple/memory/\($0).jpg" }
        let flattened = R2Storage.chunked(paths).flatMap { $0 }
        #expect(flattened.count == count)
        #expect(Set(flattened) == Set(paths))
    }
}
