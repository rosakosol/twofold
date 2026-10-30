//
//  DrawingCanvasSizeTests.swift
//  TwofoldTests
//
//  The size and shape the drawing pad is drawn and saved at.
//
//  `DrawingCanvasView` used to stretch `backgroundImage` to fill whatever size its `Canvas` was
//  given, while strokes were drawn at the absolute coordinates they were recorded at. So the render
//  size was not a detail: get it wrong by any amount and every new stroke landed displaced relative
//  to the drawing underneath it. Reported as a new layer shifting left after saving.
//
//  The editor used to measure itself with a `GeometryReader` in a `.background()` applied *after*
//  `.padding(Theme.Spacing.md)`, which measures the padded container rather than the canvas. These
//  measure both orderings against a real hosting controller, because the difference is a fact about
//  SwiftUI's modifier order rather than about this app, and it is the kind of thing that reads as
//  equivalent right up until someone looks at the pixels.
//
//  The second half is the shape (DUO-3, HOME-11): the canvas took the shape of whatever room it was
//  given — a sheet, a full-screen cover, a folded or unfolded iPhone Duo — and the saved PNG with
//  it, so a pad opened through a different route was stretched and the stretch saved. Those tests
//  render the real saved image and read its pixels.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct DrawingCanvasSizeTests {

    private let host = CGSize(width: 390, height: 700)

    /// Lays a view out in a real window and returns whatever its `GeometryReader` reported.
    ///
    /// A window is required, not a nicety: `onAppear` does not fire for a hosting controller whose
    /// view was merely sized and told to lay out. The first version of these tests did that, and
    /// every measurement came back `.zero` — which would have "passed" any assertion phrased as an
    /// inequality between two zeros.
    private func present<V: View>(_ view: V) async -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: host))
        window.rootViewController = UIHostingController(rootView: view)
        // Below `.normal`, so it can never sit above the app's own window and take its touches.
        // These tests run inside the app process; a stray visible window there is indistinguishable
        // from a frozen app.
        window.windowLevel = .normal - 1
        window.isHidden = false
        window.layoutIfNeeded()
        // One turn of the run loop for SwiftUI to run its appearance pass.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        return window
    }

    /// Fully tears a test window down. Hiding it is not enough — it keeps a hosting controller
    /// alive and stays in the scene's window list, and anything left behind here lands in the
    /// running app, because these tests are hosted by it.
    private func dismantle(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    /// The old arrangement: measured outside, after padding.
    @Test("measuring outside the padding reports the wrong size")
    func paddedContainerIsLarger() async {
        var padded: CGSize = .zero
        var inner: CGSize = .zero

        let w1 = await present(
            Color.white
                .padding(Theme.Spacing.md)
                .background(GeometryReader { geo in
                    Color.clear.onAppear { padded = geo.size }
                })
                .frame(width: host.width, height: host.height)
        )
        let w2 = await present(
            Color.white
                .background(GeometryReader { geo in
                    Color.clear.onAppear { inner = geo.size }
                })
                .padding(Theme.Spacing.md)
                .frame(width: host.width, height: host.height)
        )
        defer { dismantle(w1); dismantle(w2) }

        #expect(padded != .zero, "nothing was laid out — this test can't say anything")
        #expect(
            padded.width - inner.width == Theme.Spacing.md * 2,
            "the padded container is exactly two paddings wider, which is the whole bug"
        )
        #expect(padded.height - inner.height == Theme.Spacing.md * 2)
    }

    /// The property that actually matters: what `DrawingCanvasView` reports is its own drawing
    /// surface, whatever the caller wraps it in. A padded caller must not change the answer.
    @Test("the canvas reports its own size, not its caller's")
    func canvasReportsItsOwnSize() async {
        var bare: CGSize = .zero
        var wrapped: CGSize = .zero

        func canvas(_ report: @escaping (CGSize) -> Void) -> some View {
            DrawingCanvasView(
                elements: .constant([]),
                redoStack: .constant([]),
                tool: .pen,
                onSizeChange: report
            )
        }

        let w1 = await present(canvas { bare = $0 }.frame(width: host.width, height: host.height))

        // Exactly what the editor does to it: clipped, shadowed and padded.
        let w2 = await present(
            canvas { wrapped = $0 }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(Theme.Spacing.md)
                .frame(width: host.width, height: host.height)
        )
        defer { dismantle(w1); dismantle(w2) }

        #expect(bare != .zero, "the bare canvas never laid out")
        #expect(wrapped != .zero, "the wrapped canvas never laid out")
        // The padded one is genuinely smaller — it has less room — but what it reports is its own
        // surface, not the padded box around it. That is the invariant `save()` depends on.
        #expect(
            wrapped.width == bare.width - Theme.Spacing.md * 2,
            "the canvas reported the padded container's width instead of its own"
        )
    }

    // MARK: - Shape

    /// The rooms the editor actually gets: the Home sheet and the notification's full-screen cover
    /// on the same phone (different heights), and an iPhone Duo folded and unfolded in landscape.
    @Test(
        "the canvas is the same shape in any room it is given",
        arguments: [
            CGSize(width: 358, height: 560),
            CGSize(width: 358, height: 640),
            CGSize(width: 434, height: 520),
            CGSize(width: 900, height: 520),
        ]
    )
    func canvasKeepsItsShape(room: CGSize) async {
        var reported: CGSize = .zero
        let window = await present(
            DrawingCanvasView(
                elements: .constant([]),
                redoStack: .constant([]),
                tool: .pen,
                onSizeChange: { reported = $0 }
            )
            .frame(width: room.width, height: room.height)
        )
        defer { dismantle(window) }

        #expect(reported != .zero, "the canvas never laid out")
        #expect(
            abs(reported.width / reported.height - DrawingCanvasGeometry.aspectRatio) < 0.01,
            "a \(room) room gave a \(reported) canvas, so the pad's shape still comes from the device"
        )
        // Fitted, so it uses the room it has on its tighter axis rather than shrinking arbitrarily.
        #expect(abs(reported.width - room.width) < 0.5 || abs(reported.height - room.height) < 0.5)
    }

    @Test("the saved image is one fixed size, whatever screen it was drawn on")
    func savedImageIsFixedSize() throws {
        let image = try #require(DrawingCanvasView.renderedImage(elements: [], backgroundImage: nil))
        let cg = try #require(image.cgImage)
        #expect(cg.width == 1200)
        #expect(cg.height == 1600)
    }

    /// A pad saved before the shape was fixed: here a 1:2 image, narrower than 3:4. Drawn into the
    /// full rect it would be stretched sideways to cover the canvas, and saved that way.
    @Test("an older pad of another shape is fitted, not stretched")
    func legacyBackgroundIsFitted() throws {
        let legacy = solidImage(size: CGSize(width: 300, height: 600), color: .black)
        let image = try #require(DrawingCanvasView.renderedImage(elements: [], backgroundImage: legacy))
        let pixels = try Pixels(image)

        // Fitted into 600 x 800 pt, a 1:2 image is 400 pt wide, centred: x 100...500 pt.
        #expect(pixels.isDark(xFraction: 0.5, yFraction: 0.5), "the old drawing should still be there")
        #expect(
            !pixels.isDark(xFraction: 50.0 / 600, yFraction: 0.5),
            "the margin beside a narrower old pad is ink, so it was stretched to fill the canvas"
        )
        #expect(!pixels.isDark(xFraction: 550.0 / 600, yFraction: 0.5))
        // Fills the height, so no letterbox top and bottom.
        #expect(pixels.isDark(xFraction: 0.5, yFraction: 10.0 / 800))
    }

    /// A stroke recorded on one size of screen lands in the same place, at the same relative
    /// thickness, in the saved image — the property that broke when the canvas changed size
    /// mid-drawing (a Duo folding) and at every save, which renders at a different size from the
    /// screen.
    @Test(
        "a stroke drawn at any canvas size lands in the same place when saved",
        arguments: [CGSize(width: 358, height: 477.33), CGSize(width: 390, height: 520)]
    )
    func strokeSurvivesTheResize(drawnOn canvas: CGSize) throws {
        // What `DrawingCanvasView.handleDrag` records for a 5 pt pen line across the middle.
        let from = CGPoint(x: canvas.width * 0.25, y: canvas.height * 0.5)
        let to = CGPoint(x: canvas.width * 0.75, y: canvas.height * 0.5)
        let element = DrawingElement(
            tool: .line,
            points: [DrawingElement.normalized(from, in: canvas), DrawingElement.normalized(to, in: canvas)],
            color: .black,
            lineWidth: 5 / canvas.width
        )
        let image = try #require(DrawingCanvasView.renderedImage(elements: [element], backgroundImage: nil))
        let pixels = try Pixels(image)

        #expect(pixels.isDark(xFraction: 0.5, yFraction: 0.5), "the line isn't across the middle of the saved pad")
        #expect(pixels.isDark(xFraction: 0.3, yFraction: 0.5))
        #expect(!pixels.isDark(xFraction: 0.2, yFraction: 0.5), "the line runs past where it was drawn")
        #expect(!pixels.isDark(xFraction: 0.8, yFraction: 0.5))
        // On screen the line was 5 / width of the pad wide; scaled to the 600 pt export that is
        // over 7.5 pt, so 3.5 pt off its centre is still ink. A width left at 5 pt is not.
        let offset = 3.5 / DrawingCanvasGeometry.exportPointSize.height
        #expect(pixels.isDark(xFraction: 0.5, yFraction: 0.5 - offset), "the stroke didn't scale with the pad")
        #expect(pixels.isDark(xFraction: 0.5, yFraction: 0.5 + offset))
        #expect(!pixels.isDark(xFraction: 0.5, yFraction: 0.5 - 4 * offset))
    }

    @Test("aspect-fit centres an image on its tighter axis")
    func aspectFitRect() {
        let bounds = CGSize(width: 300, height: 400)
        // Wider than the bounds: full width, letterboxed top and bottom.
        #expect(
            DrawingCanvasGeometry.aspectFitRect(for: CGSize(width: 900, height: 520), in: bounds)
                == CGRect(x: 0, y: (400 - 300 * 520 / 900) / 2, width: 300, height: 300 * 520 / 900)
        )
        // Taller than the bounds (an old ~3:5 pad): full height, margins at the sides.
        #expect(
            DrawingCanvasGeometry.aspectFitRect(for: CGSize(width: 300, height: 500), in: bounds)
                == CGRect(x: 30, y: 0, width: 240, height: 400)
        )
        // Already the shape: the whole rect.
        #expect(
            DrawingCanvasGeometry.aspectFitRect(for: CGSize(width: 1200, height: 1600), in: bounds)
                == CGRect(origin: .zero, size: bounds)
        )
        // A degenerate image can't divide by zero.
        #expect(DrawingCanvasGeometry.aspectFitRect(for: .zero, in: bounds) == CGRect(origin: .zero, size: bounds))
    }

    // MARK: - Pixels

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// An image redrawn into a known RGBA layout, so a pixel can be read without caring how the
    /// renderer happened to encode it. Row 0 is the top of the image.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: UIImage) throws {
            let cg = try #require(image.cgImage)
            width = cg.width
            height = cg.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            try #require(drawn)
            bytes = buffer
        }

        func isDark(xFraction: CGFloat, yFraction: CGFloat) -> Bool {
            let x = min(width - 1, Int(xFraction * CGFloat(width)))
            let y = min(height - 1, Int(yFraction * CGFloat(height)))
            let i = (y * width + x) * 4
            let luminance = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
            return luminance < 128
        }
    }
}
