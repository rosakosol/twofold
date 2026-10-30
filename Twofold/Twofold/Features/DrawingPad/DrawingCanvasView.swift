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
    var color: Color = Theme.textPrimary
    /// In points on the screen as the stroke is drawn; stored as a fraction of the canvas width
    /// (see `DrawingElement`), so it scales with the drawing rather than staying 5 pt at any size.
    var lineWidth: CGFloat = 5
    /// The previously-saved pad, drawn first so new strokes layer on top of it. `nil` once the
    /// user hits Clear, so a save after clearing doesn't resurrect the old drawing underneath.
    var backgroundImage: UIImage?
    /// Reports the drawing surface's own size, measured here rather than by the caller.
    ///
    /// It has to be measured *inside* this view. The editor previously measured its own padded
    /// container, which is 2 x `Theme.Spacing.md` larger on each axis, and re-rendered into that
    /// larger frame at save time: the background (then stretched to fill the canvas) grew, the
    /// strokes (then in absolute points) did not, and the new layer landed up and to the left.
    /// Worse, it compounded: each save wrote the padded aspect ratio, which the next session
    /// stretched back before saving it padded again.
    ///
    /// Neither half of that can happen now — the canvas holds `DrawingCanvasGeometry.aspectRatio`
    /// whatever it is given, strokes are normalised, and the background is drawn aspect-fit — and
    /// saving no longer depends on this at all (`renderedImage` uses a fixed size). It stays so a
    /// caller can know what the surface actually is.
    var onSizeChange: ((CGSize) -> Void)?

    @State private var currentElement: DrawingElement?
    /// The surface's size, which a drag needs to turn a touch into a normalised point.
    @State private var surfaceSize: CGSize = .zero

    var body: some View {
        Canvas { context, size in
            if let backgroundImage {
                context.draw(
                    Image(uiImage: backgroundImage),
                    in: DrawingCanvasGeometry.aspectFitRect(for: backgroundImage.size, in: size)
                )
            }
            for element in elements {
                stroke(element, in: &context, size: size)
            }
            if let currentElement {
                stroke(currentElement, in: &context, size: size)
            }
        }
        // Here, inside the view, so no caller can give the pad a different shape. The size the
        // `GeometryReader` below reports, and the size a drag normalises against, are both this.
        .aspectRatio(DrawingCanvasGeometry.aspectRatio, contentMode: .fit)
        .background(.white)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        surfaceSize = geo.size
                        onSizeChange?(geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        surfaceSize = newSize
                        onSizeChange?(newSize)
                    }
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

    /// The pad flattened to the PNG that gets saved (and shared): always
    /// `DrawingCanvasGeometry.exportPointSize` at `exportScale`, whatever screen it was drawn on.
    /// Rendering at the on-screen size made the stored image the device's shape, which the
    /// partner's 3:4 pane then letterboxed and the next session on a different shape stretched.
    @MainActor
    static func renderedImage(elements: [DrawingElement], backgroundImage: UIImage?) -> UIImage? {
        let size = DrawingCanvasGeometry.exportPointSize
        let renderer = ImageRenderer(
            content: DrawingCanvasView(elements: .constant(elements), redoStack: .constant([]), tool: .pen, backgroundImage: backgroundImage)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = DrawingCanvasGeometry.exportScale
        return renderer.uiImage
    }

    private func stroke(_ element: DrawingElement, in context: inout GraphicsContext, size: CGSize) {
        context.stroke(
            element.path(in: size),
            with: .color(element.color),
            style: StrokeStyle(lineWidth: element.lineWidth(in: size), lineCap: .round, lineJoin: .round)
        )
    }

    private func handleDrag(_ value: DragGesture.Value) {
        // Before the first layout there is nothing to normalise against.
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return }
        let location = DrawingElement.normalized(value.location, in: surfaceSize)
        if currentElement == nil {
            let width = tool == .eraser ? lineWidth * 4 : lineWidth
            currentElement = DrawingElement(
                tool: tool,
                points: [DrawingElement.normalized(value.startLocation, in: surfaceSize)],
                color: tool == .eraser ? .white : color,
                lineWidth: width / surfaceSize.width
            )
        }
        switch tool {
        case .pen, .eraser:
            currentElement?.points.append(location)
        case .rectangle, .ellipse, .line:
            if currentElement!.points.count < 2 {
                currentElement?.points.append(location)
            } else {
                currentElement?.points[1] = location
            }
        }
    }
}
