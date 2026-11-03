//
//  DrawingPadOfflineTests.swift
//  TwofoldTests
//
//  The drawing pads with no network (HOME-9).
//
//  Signing a pad's URL is a round trip, and a failed one used to assign nil over the URL already
//  held, so both pads went blank offline although their drawings were on disk.
//

import Testing
import Foundation
import UIKit
@testable import Twofold

@MainActor
@Suite(.serialized)
struct DrawingPadOfflineTests {

    private let mine = URL(string: "https://example.invalid/couple/me/pad.png?sig=old")!
    private let theirs = URL(string: "https://example.invalid/couple/them/pad.png?sig=old")!

    @Test("a failed sign keeps the URLs the pads already had")
    func failedSignKeepsURLs() async {
        let model = AppModel()
        model.session.backendCoupleID = UUID()
        model.myDrawingURL = mine
        model.partnerDrawingURL = theirs

        await model.loadDrawingPads(sign: { _, _ in throw URLError(.notConnectedToInternet) })

        #expect(model.myDrawingURL == mine, "Offline, your pad lost its URL and went blank")
        #expect(model.partnerDrawingURL == theirs, "Offline, your partner's pad lost its URL and went blank")
    }

    @Test("a successful sign still replaces them")
    func successfulSignReplaces() async {
        let model = AppModel()
        model.session.backendCoupleID = UUID()
        model.myDrawingURL = mine
        let fresh = URL(string: "https://example.invalid/couple/me/pad.png?sig=new")!

        await model.loadDrawingPads(sign: { _, _ in fresh })

        #expect(model.myDrawingURL == fresh)
        #expect(model.partnerDrawingURL == fresh)
    }

    @Test("the offline snapshot keeps the pads' paths, without the signature")
    func snapshotKeepsUnsignedPaths() throws {
        OfflineDataCache.clear()
        defer { OfflineDataCache.clear() }
        let userID = UUID()
        OfflineDataCache.record(
            trips: [], flights: [], memories: [],
            myCity: nil, partnerCity: nil,
            myAvatarURL: nil, partnerAvatarURL: nil,
            myDrawingURL: mine, partnerDrawingURL: theirs,
            couple: nil, userID: userID
        )
        let restored = try #require(OfflineDataCache.restore(for: userID))
        #expect(restored.myDrawingURL?.path == mine.path)
        #expect(restored.partnerDrawingURL?.path == theirs.path)
        #expect(restored.myDrawingURL?.query == nil, "A signed URL's token was written to disk")
    }
}
