//
//  DrawingCanvasSizeTests.swift
//  TwofoldTests
//
//  The size the drawing pad renders at, which has to be the canvas's own.
//
//  `DrawingCanvasView` stretches `backgroundImage` to fill whatever size its `Canvas` is given,
//  while strokes are drawn at the absolute coordinates they were recorded at. So the render size is
//  not a detail: get it wrong by any amount and every new stroke lands displaced relative to the
//  drawing underneath it. Reported as a new layer shifting left after saving.
//
//  The editor used to measure itself with a `GeometryReader` in a `.background()` applied *after*
//  `.padding(Theme.Spacing.md)`, which measures the padded container rather than the canvas. These
//  measure both orderings against a real hosting controller, because the difference is a fact about
//  SwiftUI's modifier order rather than about this app, and it is the kind of thing that reads as
//  equivalent right up until someone looks at the pixels.
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
}
