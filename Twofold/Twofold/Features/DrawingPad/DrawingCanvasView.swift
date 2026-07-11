//
//  DrawingCanvasView.swift
//  Twofold
//
//  The drawing surface itself — freehand pen/eraser strokes plus drag-to-size shapes, all
//  committed as `DrawingElement`s so undo/redo (owned by the caller) can just pop the array.
//

import SwiftUI

struct DrawingCanvasView: View {
    @Binding var elements: [DrawingElement]
    @Binding var redoStack: [DrawingElement]
    var tool: DrawingTool
    var color: Color = Theme.ink
    var lineWidth: CGFloat = 5

    @State private var currentElement: DrawingElement?

    var body: some View {
        Canvas { context, _ in
            for element in elements {
                stroke(element, in: &context)
            }
            if let currentElement {
                stroke(currentElement, in: &context)
            }
        }
        .background(.white)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(handleDrag)
                .onEnded { _ in
                    if let currentElement {
                        elements.append(currentElement)
                        redoStack.removeAll()
                    }
                    currentElement = nil
                }
        )
    }

    private func stroke(_ element: DrawingElement, in context: inout GraphicsContext) {
        context.stroke(
            element.path,
            with: .color(element.color),
            style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func handleDrag(_ value: DragGesture.Value) {
        if currentElement == nil {
            currentElement = DrawingElement(
                tool: tool,
                points: [value.startLocation],
                color: tool == .eraser ? .white : color,
                lineWidth: tool == .eraser ? lineWidth * 4 : lineWidth
            )
        }
        switch tool {
        case .pen, .eraser:
            currentElement?.points.append(value.location)
        case .rectangle, .ellipse, .line:
            if currentElement!.points.count < 2 {
                currentElement?.points.append(value.location)
            } else {
                currentElement?.points[1] = value.location
            }
        }
    }
}
