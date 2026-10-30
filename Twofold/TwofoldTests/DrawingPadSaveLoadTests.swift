//
//  DrawingPadSaveLoadTests.swift
//  TwofoldTests
//
//  The two ways the drawing pad lost a drawing (HOME-3, HOME-4).
//
//  Loading: every failure used to look like an empty pad, and Save then uploaded only the new
//  strokes over the drawing that hadn't loaded. Saving: a failed upload set `myDrawingURL` to nil,
//  so the next session had nothing to load and did the same. Both are exercised through the real
//  types with the network replaced, never the network itself.
//

import Testing
import Foundation
import UIKit
@testable import Twofold

@MainActor
struct DrawingPadSaveLoadTests {

    private static let url = URL(string: "https://example.invalid/couple/person/pad.png?sig=abc")!

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private var png: Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 3, height: 4), format: format).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 4))
        }
    }

    private func isLoaded(_ result: DrawingPadLoadResult) -> Bool {
        if case .loaded = result { return true }
        return false
    }

    private func isBlank(_ result: DrawingPadLoadResult) -> Bool {
        if case .blank = result { return true }
        return false
    }

    private func isFailed(_ result: DrawingPadLoadResult) -> Bool {
        if case .failed = result { return true }
        return false
    }

    // MARK: - Loading

    @Test("offline with nothing cached is a failure, not an empty pad")
    func offlineIsFailure() async {
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in throw URLError(.notConnectedToInternet) },
            cached: { _ in nil },
            store: { _, _ in }
        )
        #expect(isFailed(result), "a failed load reported as blank lets Save overwrite the drawing")
    }

    @Test("offline falls back to the disk copy")
    func offlineUsesCache() async {
        let cachedImage = UIImage(data: png)!
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in throw URLError(.timedOut) },
            cached: { _ in cachedImage },
            store: { _, _ in }
        )
        #expect(isLoaded(result))
    }

    /// An expired signature or a server error answers with a body that isn't an image.
    @Test("a 403 or 500 is a failure", arguments: [403, 500])
    func serverErrorIsFailure(status: Int) async {
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in (Data("<Error/>".utf8), Self.response(status)) },
            cached: { _ in nil },
            store: { _, _ in }
        )
        #expect(isFailed(result))
    }

    @Test("a 200 that doesn't decode is a failure")
    func undecodableIsFailure() async {
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in (Data("not a png".utf8), Self.response(200)) },
            cached: { _ in nil },
            store: { _, _ in }
        )
        #expect(isFailed(result))
    }

    /// Someone who has never drawn has a signed URL with nothing behind it. They must be able to
    /// save a first drawing without being told they're replacing one.
    @Test("a 404 is a blank pad, and the disk copy is not used over it")
    func notFoundIsBlank() async {
        let cachedImage = UIImage(data: png)!
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in (Data(), Self.response(404)) },
            cached: { _ in cachedImage },
            store: { _, _ in }
        )
        #expect(isBlank(result))
    }

    @Test("no URL is a blank pad")
    func noURLIsBlank() async {
        let result = await DrawingPadLoader.load(
            nil,
            fetch: { _ in Issue.record("nothing to fetch"); throw URLError(.badURL) },
            cached: { _ in nil },
            store: { _, _ in }
        )
        #expect(isBlank(result))
    }

    @Test("a fetched pad loads and refreshes the disk copy")
    func fetchedPadLoads() async {
        var stored: Data?
        let bytes = png
        let result = await DrawingPadLoader.load(
            Self.url,
            fetch: { _ in (bytes, Self.response(200)) },
            cached: { _ in nil },
            store: { data, _ in stored = data }
        )
        #expect(isLoaded(result))
        #expect(stored == bytes)
    }

    // MARK: - Saving

    @Test("a failed upload keeps the saved drawing's URL and reports failure")
    func failedSaveKeepsURL() async {
        let model = AppModel()
        model.myDrawingURL = Self.url

        let saved = await model.commitMyDrawing(imageData: png) { _ in
            throw R2Storage.StorageError.uploadFailed
        }

        #expect(saved == false, "the editor dismisses, and the strokes are lost, on a reported success")
        #expect(model.myDrawingURL == Self.url, "a failed save cleared the URL, so the next session opens blank")
    }
}
