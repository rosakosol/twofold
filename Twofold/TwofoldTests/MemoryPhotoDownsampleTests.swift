//
//  MemoryPhotoDownsampleTests.swift
//  TwofoldTests
//
//  Map pins decode photos down to roughly the size they draw at. The saving is the whole point,
//  so "it returns an image" is not enough — these check it returns a *smaller* one, and that the
//  picture itself survives the trip.
//

import Foundation
import Testing
import UIKit
@testable import Twofold

@MainActor
struct MemoryPhotoDownsampleTests {

    /// A JPEG of a given pixel size. Two colours rather than one flat fill, so orientation and
    /// aspect are observable in the output rather than being a uniform block that any transform
    /// would appear to survive.
    private func jpeg(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: max(1, height / 4)))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    @Test("a full-size upload comes back at roughly the pin's size")
    func downsamplesToTarget() throws {
        // The real shape: `MemoryEditingKit` caps uploads at 1600px, the pin asks for 192.
        let data = jpeg(width: 1600, height: 1600)
        let image = try #require(MemoryPhotoView.downsampled(data, maxPixelSize: 192))

        #expect(max(image.size.width, image.size.height) <= 192)
        // The saving this exists for: ~70x fewer pixels decoded per pin.
        let fullPixels = 1600.0 * 1600.0
        let thumbPixels = image.size.width * image.size.height
        #expect(thumbPixels < fullPixels / 50)
    }

    @Test("a non-square photo keeps its shape")
    func preservesAspectRatio() throws {
        let data = jpeg(width: 1600, height: 800)
        let image = try #require(MemoryPhotoView.downsampled(data, maxPixelSize: 192))

        #expect(max(image.size.width, image.size.height) <= 192)
        // 2:1 in, 2:1 out. A thumbnail forced square would crop or squash every landscape photo.
        let ratio = image.size.width / image.size.height
        #expect(abs(ratio - 2.0) < 0.05, "expected roughly 2:1, got \(ratio)")
    }

    /// An image already smaller than the target must not be scaled *up* — that would decode more
    /// pixels than the file holds and blur the result for no gain.
    @Test("a photo smaller than the target is left alone")
    func doesNotUpscale() throws {
        let data = jpeg(width: 100, height: 100)
        let image = try #require(MemoryPhotoView.downsampled(data, maxPixelSize: 192))
        #expect(max(image.size.width, image.size.height) <= 100)
    }

    /// Bytes that are not an image at all. The pin should fall back rather than trap — a corrupt
    /// cache entry is a thing that happens, and it must not take the map down with it.
    @Test("undecodable data returns nil rather than crashing")
    func handlesGarbage() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(MemoryPhotoView.downsampled(garbage, maxPixelSize: 192) == nil)
    }
}
