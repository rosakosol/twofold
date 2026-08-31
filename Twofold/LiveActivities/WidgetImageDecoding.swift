//
//  WidgetImageDecoding.swift
//  LiveActivities
//
//  Decoding an image down to the size a widget will actually draw it at, instead of at whatever
//  resolution it was saved.
//
//  A widget extension gets a hard memory ceiling (tens of megabytes) and WidgetKit archives the
//  rendered view to hand to the Home Screen, which has its own size limit. A drawing pad is
//  exported at `renderer.scale = 2` over the full canvas, so its PNG decodes to a bitmap of
//  several megabytes; the Medium Drawing Pad widget decodes *two* of them plus two avatars into a
//  pane about 150 points wide. The Small size decodes one image and renders; Medium showed the
//  grey placeholder, with `com.apple.chrono:archiving` logging faults underneath it — the shape of
//  a render that never made it out of the extension.
//
//  Downsampling at decode time is the standard remedy: ImageIO builds the thumbnail straight from
//  the source without ever materialising the full-size bitmap, so the cost is bounded by what's
//  drawn rather than by what was saved.
//

import ImageIO
import SwiftUI
import UIKit

enum WidgetImageDecoding {

    /// Decodes `data` so its longest edge is at most `maxPixelSize`, never larger than the source.
    ///
    /// `maxPixelSize` is in *pixels*, so callers pass the point size they draw at multiplied by a
    /// screen scale — `pointSize:` below does that, and is what every call site actually uses.
    static func downsampled(_ data: Data?, maxPixelSize: Int) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honour EXIF orientation — a photo taken sideways would otherwise draw sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    /// The common case: "I draw this at N points." Multiplied by 3 for the densest screen this
    /// runs on, so the image is never upscaled on any device and never much larger than needed.
    static func downsampled(_ data: Data?, pointSize: CGFloat) -> UIImage? {
        downsampled(data, maxPixelSize: Int((pointSize * 3).rounded()))
    }
}
