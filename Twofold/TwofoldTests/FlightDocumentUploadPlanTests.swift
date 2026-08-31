//
//  FlightDocumentUploadPlanTests.swift
//  TwofoldTests
//
//  What happens to a file attached to a flight through the Files picker.
//
//  The gap these pin: the Photos and camera buttons resized and re-encoded whatever they captured,
//  but the Files button beside them uploaded raw bytes. The same photo therefore cost several
//  megabytes or a few hundred kilobytes depending only on which menu item was tapped — and a photo
//  saved to Files is an entirely ordinary way to attach a boarding pass. Nothing capped the other
//  direction either, so a 40MB scanned PDF went up untouched.
//

import Testing
import Foundation
import UIKit
@testable import Twofold

struct FlightDocumentUploadPlanTests {

    /// A real JPEG of a given pixel size, so "would this decode as an image" is answered by the
    /// same decoder the app uses rather than by a stubbed guess.
    private func jpeg(side: CGFloat, quality: CGFloat = 1) -> Data {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            // Noise rather than flat colour — a solid fill compresses to almost nothing, which
            // would make a "full resolution photo" fixture smaller than a real thumbnail.
            for x in stride(from: 0, to: side, by: 4) {
                for y in stride(from: 0, to: side, by: 4) {
                    UIColor(hue: (x + y).truncatingRemainder(dividingBy: 360) / 360,
                            saturation: 0.9, brightness: 0.9, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
        return image.jpegData(compressionQuality: quality)!
    }

    /// Bytes that are definitely not a decodable image — a PDF header and filler.
    private func document(bytes: Int) -> Data {
        var data = Data("%PDF-1.7\n".utf8)
        data.append(Data(repeating: 0x41, count: max(0, bytes - data.count)))
        return data
    }

    // MARK: - The reported gap

    @Test("a photo picked through Files is re-encoded, not uploaded raw")
    func imageFilesAreRecompressed() throws {
        guard case .recompressImage = FlightDocumentUploadPlan.plan(for: jpeg(side: 3000)) else {
            Issue.record("A full-resolution photo should be re-encoded, not uploaded as-is")
            return
        }
    }

    /// The saving is the whole point of the fix, so it's measured rather than assumed.
    @Test("re-encoding a full-resolution photo is a large saving")
    func recompressionActuallyShrinksTheFile() throws {
        let original = jpeg(side: 3000)
        guard case .recompressImage(let image) = FlightDocumentUploadPlan.plan(for: original) else {
            Issue.record("Expected an image plan")
            return
        }
        let recompressed = try #require(image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.85))
        #expect(recompressed.count < original.count / 2,
                "Expected a real saving, got \(original.count) → \(recompressed.count) bytes")
    }

    /// HEIC, PNG, a file with no extension at all — the decision is made by decoding, so none of
    /// them need special-casing.
    @Test("an image with no useful filename still gets re-encoded")
    func formatIsDecidedByDecodingNotByExtension() {
        guard case .recompressImage = FlightDocumentUploadPlan.plan(for: jpeg(side: 1200)) else {
            Issue.record("Extension-independent decoding should still recognise this as an image")
            return
        }
    }

    // MARK: - Files that can't be made smaller

    @Test("a normal PDF boarding pass is uploaded untouched")
    func smallDocumentsUploadAsIs() {
        guard case .uploadAsIs = FlightDocumentUploadPlan.plan(for: document(bytes: 300_000)) else {
            Issue.record("A small PDF should upload as-is")
            return
        }
    }

    @Test("an oversized document is refused rather than silently uploaded")
    func oversizedDocumentsAreRefused() {
        let limit = FlightDocumentUploadPlan.defaultLimit
        guard case .tooLarge(let bytes, let reported) = FlightDocumentUploadPlan.plan(for: document(bytes: limit + 1)) else {
            Issue.record("A document past the ceiling should be refused")
            return
        }
        #expect(bytes == limit + 1)
        // Reported back so the message can name both numbers — "that file is 12 MB, the limit
        // is 10 MB" is actionable in a way "too large" isn't.
        #expect(reported == limit)
    }

    @Test("a document exactly on the limit is allowed")
    func theLimitIsInclusive() {
        guard case .uploadAsIs = FlightDocumentUploadPlan.plan(for: document(bytes: FlightDocumentUploadPlan.defaultLimit)) else {
            Issue.record("The ceiling should be inclusive")
            return
        }
    }

    /// A huge *image* is never refused — it's re-encoded instead, which is the better outcome and
    /// the reason the image branch is checked first.
    @Test("a huge photo is shrunk rather than refused")
    func largeImagesAreRecompressedNotRejected() {
        let big = jpeg(side: 4000)
        guard case .recompressImage = FlightDocumentUploadPlan.plan(for: big, limit: 1024) else {
            Issue.record("An image past the ceiling should be re-encoded, not refused")
            return
        }
    }

    @Test("an empty file isn't mistaken for a document worth uploading")
    func emptyDataIsNotAnImage() {
        guard case .uploadAsIs = FlightDocumentUploadPlan.plan(for: Data()) else {
            Issue.record("Empty data has nothing to re-encode and nothing to refuse")
            return
        }
    }
}
