//
//  DrawingSticker.swift
//  Twofold
//
//  A drawing as a die-cut sticker: the strokes on a white edge that follows their shape, on a
//  transparent background (SHARE_REDESIGN.md §4, "Making the sticker").
//
//  The pad is stored as a flattened bitmap on white, not as strokes, so this works from the bitmap.
//  That turns out to be convenient: the white the strokes already sit on *is* the die-cut edge.
//  Find the ink, grow that region outwards so nearby strokes merge into one shape, round it off,
//  and keep the original picture only inside it.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

nonisolated enum DrawingSticker {
    /// Anything this far from white in any channel is ink. Low enough to catch a cream outline,
    /// high enough to ignore JPEG-ish noise on the paper.
    private static let inkThreshold: UInt8 = 14
    /// The white edge, as a share of the sticker's longest side.
    private static let edgeFraction: CGFloat = 0.03
    /// Larger pads are scaled down first; the dilation is the slow part.
    private static let maxSide: CGFloat = 1400

    /// The sticker, or nil when the pad has nothing drawn on it.
    static func make(from drawing: UIImage) -> UIImage? {
        guard let source = scaled(drawing), let (mask, picture, inkBounds) = inkMask(source) else { return nil }

        let longest = max(inkBounds.width, inkBounds.height)
        let edge = max(6, (longest * edgeFraction).rounded())
        let margin = edge * 2

        // Room around the canvas so the grown edge isn't cut off where ink touches the border.
        let padded = CGRect(x: -margin, y: -margin, width: CGFloat(source.width) + margin * 2, height: CGFloat(source.height) + margin * 2)

        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = mask.clampedToExtent().cropped(to: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            .composited(over: CIImage(color: .black).cropped(to: padded))
        dilate.radius = Float(edge)

        // A blur and a threshold turn the dilation's blocky corners into round ones.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = dilate.outputImage
        blur.radius = Float(edge * 0.4)
        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = blur.outputImage?.cropped(to: padded)
        threshold.threshold = 0.5

        let blend = CIFilter.blendWithMask()
        // The original picture, with white beyond its own edges so the grown margin is white too.
        blend.inputImage = picture.composited(over: CIImage(color: .white).cropped(to: padded))
        blend.backgroundImage = CIImage(color: .clear).cropped(to: padded)
        blend.maskImage = threshold.outputImage

        // Core Image's origin is the bottom left; the ink bounds were measured from the top.
        let flippedInk = CGRect(
            x: inkBounds.minX,
            y: CGFloat(source.height) - inkBounds.maxY,
            width: inkBounds.width,
            height: inkBounds.height
        )
        let crop = flippedInk.insetBy(dx: -margin, dy: -margin).intersection(padded)

        let context = CIContext()
        guard let output = blend.outputImage?.cropped(to: crop),
              let cgImage = context.createCGImage(output, from: crop, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { return nil }
        return UIImage(cgImage: cgImage, scale: drawing.scale, orientation: .up)
    }

    // MARK: - Steps

    private static func scaled(_ image: UIImage) -> CGImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxSide / max(pixelSize.width, pixelSize.height))
        let size = CGSize(width: (pixelSize.width * factor).rounded(), height: (pixelSize.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// White where there is ink, black elsewhere; the picture with light strokes outlined; and the
    /// ink's bounding box (top-left origin).
    private static func inkMask(_ image: CGImage) -> (mask: CIImage, picture: CIImage, bounds: CGRect)? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let cutoff = 255 - inkThreshold
        // The outermost few pixels are treated as paper. A screenshot of a pad brings rounded-corner
        // remnants with it, and those would each become a white blob at a corner of the sticker.
        let border = 3
        var ink = [Bool](repeating: false, count: width * height)
        for y in border..<max(border, height - border) {
            for x in border..<max(border, width - border) {
                let i = (y * width + x) * 4
                ink[y * width + x] = pixels[i] < cutoff || pixels[i + 1] < cutoff || pixels[i + 2] < cutoff
            }
        }

        var mask = [UInt8](repeating: 0, count: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where ink[y * width + x] {
                // A stray dot with almost no ink around it isn't part of the drawing. Left in, it
                // grows its own little white island and stretches the sticker to reach it.
                var neighbours = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < width, ny < height, ink[ny * width + nx] { neighbours += 1 }
                    }
                }
                guard neighbours >= 3 else { continue }
                let i = (y * width + x) * 4
                mask[i] = 255; mask[i + 1] = 255; mask[i + 2] = 255; mask[i + 3] = 255
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        for i in stride(from: 3, to: mask.count, by: 4) { mask[i] = 255 }

        outlineLightStrokes(&pixels, ink: ink, width: width, height: height)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        let picture = CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let data = Data(mask)
        let ciMask = CIImage(
            bitmapData: data,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (ciMask, picture, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// A very light stroke (a cream pen) sits on the sticker's white edge with almost no contrast, so
    /// the paper right around it gets a faint warm grey. Only strokes that are light *and* have no
    /// dark ink nearby count: the pale anti-aliased fringe of a black line would otherwise qualify,
    /// and every dark stroke would come out looking a little thicker.
    private static func outlineLightStrokes(_ pixels: inout [UInt8], ink: [Bool], width: Int, height: Int) {
        let radius = 2
        func luminance(_ index: Int) -> Int {
            let i = index * 4
            return (2126 * Int(pixels[i]) + 7152 * Int(pixels[i + 1]) + 722 * Int(pixels[i + 2])) / 10_000
        }
        func hasDarkInk(nearX x: Int, y: Int) -> Bool {
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let index = ny * width + nx
                    if ink[index], luminance(index) < 150 { return true }
                }
            }
            return false
        }

        func isLight(_ index: Int) -> Bool { ink[index] && luminance(index) > 200 }
        /// A stroke has light neighbours along it; a stray speck of noise doesn't.
        func isInLightStroke(x: Int, y: Int) -> Bool {
            var count = 0
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height, isLight(ny * width + nx) { count += 1 }
                }
            }
            return count >= 5
        }

        var outline = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard isLight(index), isInLightStroke(x: x, y: y), !hasDarkInk(nearX: x, y: y) else { continue }
                for dy in -radius...radius {
                    for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbour = ny * width + nx
                        if !ink[neighbour] { outline[neighbour] = true }
                    }
                }
            }
        }

        let colour = Theme.Share.stickerLightOutline
        for index in 0..<(width * height) where outline[index] {
            let i = index * 4
            pixels[i] = colour.red
            pixels[i + 1] = colour.green
            pixels[i + 2] = colour.blue
        }
    }
}
