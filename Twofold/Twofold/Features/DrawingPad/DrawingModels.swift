//
//  DrawingModels.swift
//  Twofold
//

import SwiftUI

enum DrawingTool: CaseIterable, Hashable {
    case pen, eraser, rectangle, ellipse, line

    var systemImage: String {
        switch self {
        case .pen: "pencil"
        case .eraser: "eraser"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        }
    }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .eraser: "Eraser"
        case .rectangle: "Rectangle"
        case .ellipse: "Circle"
        case .line: "Line"
        }
    }
}

/// One committed stroke or shape on the canvas. Freehand tools (`pen`/`eraser`) store every
/// point along the drag; shape tools only ever need the drag's start/end points.
///
/// Stored in the canvas's own unit square, not in points: `points` are 0...1 of the canvas's width
/// and height, and `lineWidth` is a fraction of its width. Absolute points were only right at the
/// size they were recorded at. Folding an iPhone Duo, rotating, or saving (which renders at
/// `DrawingCanvasGeometry.exportPointSize`, not the screen's size) all change that size, and the
/// strokes stayed where they were while the background moved under them. Normalised, every size
/// of the same-shaped canvas draws the same picture.
struct DrawingElement: Identifiable {
    let id = UUID()
    var tool: DrawingTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat

    /// A point on a canvas of `size`, as the unit-square point `points` holds.
    static func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    /// The stroke width on a canvas of `size`.
    func lineWidth(in size: CGSize) -> CGFloat {
        lineWidth * size.width
    }

    /// The element drawn on a canvas of `size`.
    func path(in size: CGSize) -> Path {
        let points = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        switch tool {
        case .pen, .eraser:
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        case .rectangle:
            guard let start = points.first, let end = points.last else { return path }
            path.addRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .ellipse:
            guard let start = points.first, let end = points.last else { return path }
            path.addEllipse(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .line:
            guard let start = points.first, let end = points.last else { return path }
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }
}

/// The pad's one shape and its saved size, independent of whatever screen it is drawn on.
///
/// The canvas used to take whatever room it was given, so its shape came from the device and the
/// presentation: a `.sheet` from Home and a `fullScreenCover` from a notification gave two
/// different heights on the same phone, and an iPhone Duo goes from roughly 434 x 520 folded to
/// 900 x 520 unfolded. The saved PNG was that shape, and the next session stretched it into the
/// new one before saving the stretch back, so a pad opened through the "other" route drifted
/// taller or wider every time. One fixed aspect ratio and one fixed export size make the stored
/// drawing the same shape whoever opens it, wherever.
enum DrawingCanvasGeometry {
    /// Width to height. 3:4 to match `DrawingPadPairView`'s panes, so the partner sees the pad
    /// edge to edge instead of letterboxed.
    static let aspectRatio: CGFloat = 3.0 / 4.0

    /// The saved PNG is this many points at `exportScale`, i.e. 1200 x 1600 pixels. Fixed, so two
    /// phones saving the same drawing write the same image.
    static let exportPointSize = CGSize(width: 600, height: 800)
    static let exportScale: CGFloat = 2

    /// Where an image goes when it is drawn into `bounds` without being distorted: scaled to fit,
    /// centred. The background is drawn here rather than into the full rect, so a pad saved before
    /// the shape was fixed (any aspect at all) is letterboxed on the white paper instead of being
    /// stretched, and the next save keeps it letterboxed rather than baking a stretch in.
    static func aspectFitRect(for imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
