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
    /// The previously-saved pad, drawn first so new strokes layer on top of it. `nil` once the
    /// user hits Clear, so a save after clearing doesn't resurrect the old drawing underneath.
    var backgroundImage: UIImage?
    /// Reports the drawing surface's own size, measured here rather than by the caller.
    ///
    /// It has to be measured *inside* this view. `backgroundImage` is stretched to fill whatever
    /// size the `Canvas` is given, while strokes are drawn at the absolute coordinates they were
    /// recorded at — so a size that is even slightly wrong shifts every new stroke relative to the
    /// drawing underneath it. The editor previously measured its own padded container, which is
    /// 2 x `Theme.Spacing.md` larger on each axis, and re-rendered into that larger frame at save
    /// time: the background grew, the strokes did not, and the new layer landed up and to the left.
    ///
    /// Worse, it compounded. Each save wrote an image with the padded aspect ratio, which the next
    /// session stretched back into the true canvas before saving it padded again, so a pad drawn on
    /// repeatedly drifted a little further every time.
    ///
    /// Reporting from in here means no caller can get it wrong by adding a modifier.
    var onSizeChange: ((CGSize) -> Void)?

    @State private var currentElement: DrawingElement?

    var body: some View {
        Canvas { context, size in
            if let backgroundImage {
                context.draw(Image(uiImage: backgroundImage), in: CGRect(origin: .zero, size: size))
            }
            for element in elements {
                stroke(element, in: &context)
            }
            if let currentElement {
                stroke(currentElement, in: &context)
            }
        }
        .background(.white)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onSizeChange?(geo.size) }
                    .onChange(of: geo.size) { _, newSize in onSizeChange?(newSize) }
            }
        )
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
