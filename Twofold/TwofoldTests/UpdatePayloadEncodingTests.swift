//
//  UpdatePayloadEncodingTests.swift
//  TwofoldTests
//
//  Whether a nil in an update payload means "set this to null" or "leave this alone".
//
//  Swift decides that for you, and picks the wrong one for most of these: the *synthesised*
//  `Encodable` for an optional property calls `encodeIfPresent`, which omits the key. A PATCH built
//  from it therefore says nothing about the column, and PostgREST leaves it as it was.
//
//  That is how unlinking a flight from a trip silently did nothing. `TripIDUpdate(tripId: nil)`
//  encoded to `{}`, the server kept the link, and the app looked correct only because the local
//  edit is applied optimistically — the flight reappeared on the trip at the next full refresh,
//  which is whenever anything else was added.
//
//  The distinction cannot be inferred from the type, so it is asserted here per payload. These
//  encode the same structs the app sends, through the same `JSONEncoder`, and read the bytes.
//

import Testing
import Foundation
@testable import Twofold

struct UpdatePayloadEncodingTests {

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    /// The reported bug. Unlinking has to write a null.
    @Test("unlinking a flight writes trip_id null, not an empty patch")
    func unlinkWritesNull() throws {
        let encoded = try json(BackendService.tripIDUpdateForTesting(tripID: nil))
        #expect(encoded.contains("\"trip_id\":null"), "got \(encoded) — an empty patch changes nothing")
    }

    @Test("linking a flight still writes the trip id")
    func linkWritesTheID() throws {
        let id = UUID()
        let encoded = try json(BackendService.tripIDUpdateForTesting(tripID: id))
        #expect(encoded.contains(id.uuidString), "got \(encoded)")
        #expect(!encoded.contains("null"))
    }

    /// Same shape, different screen: clearing a trip's notes must clear them.
    @Test("clearing trip notes writes null")
    func clearingNotesWritesNull() throws {
        let encoded = try json(BackendService.tripNotesUpdateForTesting(notes: nil))
        #expect(encoded.contains("\"notes\":null"), "got \(encoded)")
    }

    @Test("keeping trip notes still writes them")
    func keepingNotesWritesThem() throws {
        let encoded = try json(BackendService.tripNotesUpdateForTesting(notes: "Ferry at six"))
        #expect(encoded.contains("Ferry at six"), "got \(encoded)")
    }

    /// A memory losing its place has the same requirement, and the other fields must survive the
    /// hand-written encoder — the risk of writing one is forgetting a key.
    @Test("a memory with no place writes place_id null, and keeps its other fields")
    func memoryWithoutPlaceWritesNull() throws {
        let encoded = try json(
            BackendService.memoryUpdateForTesting(placeID: nil, title: "Ferry", note: "Rough crossing")
        )
        #expect(encoded.contains("\"place_id\":null"), "got \(encoded)")
        #expect(encoded.contains("Ferry"), "title was dropped by the hand-written encoder")
        #expect(encoded.contains("Rough crossing"), "note was dropped by the hand-written encoder")
        #expect(encoded.contains("occurred_at"), "occurred_at was dropped by the hand-written encoder")
    }

    /// The deliberate opposite, asserted so nobody "fixes" it to match the others. A routine
    /// subscription re-check reconfirms `active` without knowing the tier, and must leave the tier
    /// column alone rather than blanking it.
    @Test("a subscription re-check with no tier omits the column, on purpose")
    func subscriptionUpdateOmitsAbsentTier() throws {
        let encoded = try json(
            BackendService.subscriptionStatusUpdateForTesting(active: true, tier: nil)
        )
        #expect(!encoded.contains("subscription_tier"), "got \(encoded) — this one must NOT write null")
        #expect(encoded.contains("\"subscription_active\":true"))
    }
}
