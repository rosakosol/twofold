//
//  SheetDetentWidthTests.swift
//  TwofoldTests
//
//  Why the memories map panel got wider as you pulled it up.
//
//  A sheet below full height is drawn as an inset card, held in from both screen edges. `.large` is
//  the one detent that isn't: it goes edge to edge. So a sheet offering `[.height(220), .large]`
//  changes width as well as height when it expands, and the card appears to grow sideways out of
//  the screen — which is not what dragging a panel upward is supposed to do.
//
//  There is no modifier that keeps the inset appearance at `.large`; the fix is to expand to a
//  height just short of full instead. That is not obvious from reading it, and `.large` is the
//  natural thing for someone to reach for later, so the measurement is kept here.
//
//  Measured off the real presentation, not asserted from documentation: the sheet's own
//  `UIDropShadowView` is the layer UIKit insets, so its frame in window coordinates is where the
//  card actually sits.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct SheetDetentWidthTests {

    /// Portrait iPhone 17 Pro, in points.
    private static let screen = CGSize(width: 402, height: 874)

    private struct Host: View {
        let detents: Set<PresentationDetent>
        @Binding var selection: PresentationDetent
        var body: some View {
            Color.clear.sheet(isPresented: .constant(true)) {
                Color.clear.presentationDetents(detents, selection: $selection)
            }
        }
    }

    /// Presents a sheet for real and returns the card's frame in window coordinates.
    private func cardFrame(detents: Set<PresentationDetent>, at selection: PresentationDetent) async -> CGRect {
        // `makeKeyAndVisible` below takes key status from whatever holds it, and this measures a
        // presented card — both of which other suites are also doing. See WindowPresentationTestLock.
        await WindowPresentationTestLock.withExclusiveWindow {
            await cardFrameLocked(detents: detents, at: selection)
        }
    }

    private func cardFrameLocked(detents: Set<PresentationDetent>, at selection: PresentationDetent) async -> CGRect {
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.screen))
        var current = selection
        let host = UIHostingController(
            rootView: Host(detents: detents, selection: Binding(get: { current }, set: { current = $0 }))
        )
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()

        for _ in 0..<60 where host.presentedViewController == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(300))

        // Walk out to the view UIKit insets — the drop-shadow view is the card itself, where the
        // hosting view inside it always reports the full screen width.
        var view: UIView? = host.presentedViewController?.view
        var frame = CGRect.zero
        while let current = view {
            if String(describing: type(of: current)).contains("DropShadow") {
                frame = current.convert(current.bounds, to: nil)
                break
            }
            view = current.superview
        }
        window.isHidden = true
        return frame
    }

    // The view's own values, not copies. Copies would go on agreeing with each other after
    // someone set the real one back to `.large`.
    private static let peek = MemoriesMapView.peekDetent
    private static let expanded = MemoriesMapView.expandedDetent

    /// The regression: expanding must not change the width.
    @Test("the panel keeps its width when it expands")
    func widthIsUnchangedByExpanding() async {
        let detents: Set<PresentationDetent> = [Self.peek, Self.expanded]
        let small = await cardFrame(detents: detents, at: Self.peek)
        let big = await cardFrame(detents: detents, at: Self.expanded)

        #expect(small.width > 0, "the sheet never presented")
        #expect(big.width == small.width, "peek \(small.width)pt, expanded \(big.width)pt")
        #expect(big.minX == small.minX, "peek x=\(small.minX), expanded x=\(big.minX)")
        // And it did actually get taller, or the test above passes for the wrong reason.
        #expect(big.height > small.height)
    }

    /// The negative control, and the reason the expanded detent is a fraction rather than `.large`.
    /// Without this, the test above would keep passing if someone switched back — it only compares
    /// two detents to each other, and `.large` compared against `.large` is consistent too.
    @Test("`.large` is what changes the width")
    func largeGoesEdgeToEdge() async {
        let peekFrame = await cardFrame(detents: [Self.peek, .large], at: Self.peek)
        let largeFrame = await cardFrame(detents: [Self.peek, .large], at: .large)

        #expect(peekFrame.width < largeFrame.width, "peek \(peekFrame.width)pt vs large \(largeFrame.width)pt — sheets no longer inset, so the fraction is no longer needed")
        #expect(largeFrame.width == Self.screen.width, "`.large` should span the screen")
        #expect(peekFrame.minX > 0, "a partial detent should be inset from the edge")
    }

    /// The expanded detent has to actually be worth expanding to — a fraction that quietly resolved
    /// to something short would keep the width and lose the point.
    ///
    /// Measured against `.large` rather than against the screen, because a sheet never reaches the
    /// screen's height: it stops short of the top, and the frame this walks out to is scaled. On a
    /// 874pt screen `.large` itself measures 820pt here. The original assertion compared against
    /// 0.9 x screen = 786.6pt, which is above what `.fraction(0.98)` can produce — it was passing
    /// only while this detached window reported no safe-area insets, and started failing with no
    /// code change on either side of it. `.large` is the real ceiling, so it is the thing to
    /// compare to, and both sides now come through the same measurement path.
    @Test("expanding still fills most of the screen")
    func expandedIsNearlyFullHeight() async {
        let expandedFrame = await cardFrame(detents: [Self.peek, Self.expanded], at: Self.expanded)
        let fullFrame = await cardFrame(detents: [Self.peek, .large], at: .large)

        #expect(fullFrame.height > 0, "the sheet never presented")
        #expect(
            expandedFrame.height > fullFrame.height * 0.9,
            "expanded to \(expandedFrame.height)pt of the \(fullFrame.height)pt a full sheet gets"
        )
    }
}
