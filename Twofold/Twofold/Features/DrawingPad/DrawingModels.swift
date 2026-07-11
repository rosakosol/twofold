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
struct DrawingElement: Identifiable {
    let id = UUID()
    var tool: DrawingTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat

    var path: Path {
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
