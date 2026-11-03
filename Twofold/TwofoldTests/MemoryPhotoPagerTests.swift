//
//  MemoryPhotoPagerTests.swift
//  TwofoldTests
//
//  Each page of a multi-photo memory draws through `MemoryPhotoView` (HOME-20), so a photo already
//  in the cache draws without a network — the pager used `AsyncImage`, which drew grey offline.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct MemoryPhotoPagerTests {

    @Test("a page for a cached photo draws the photo, not the placeholder")
    func cachedPageDraws() throws {
        let photo = MemoryPhoto(
            id: UUID(),
            path: "test/\(UUID())/page.jpg",
            url: URL(string: "https://example.invalid/never-fetched.jpg")!
        )
        let red = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        ImageMemoryCache.memoryPhotos.store(red, for: photo.path)

        let renderer = ImageRenderer(content: MemoryPhotoView(photo: photo, seed: 0, cornerRadius: 0).frame(width: 20, height: 20))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        let pixel = try #require(Self.centrePixel(image))
        #expect(pixel.red > 200 && pixel.green < 60 && pixel.blue < 60, "Drew \(pixel), not the cached photo")
    }

    private static func centrePixel(_ image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (bytes[0], bytes[1], bytes[2])
    }
}
