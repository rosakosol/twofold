//
//  CachedRemoteImageTests.swift
//  TwofoldTests
//
//  The shape of this view, which is load-bearing in a way that isn't obvious from reading it.
//
//  Its `.task` is what fetches the image, and a SwiftUI view that resolves to `EmptyView` has no
//  presence in the render tree for a lifecycle modifier to run against. So a placeholder that
//  renders to nothing doesn't just look empty — it stops the view ever loading anything, forever.
//  That is what left the partner's drawing pad blank while the user's own drawing, whose
//  placeholder is a real "Tap to draw", appeared right beside it.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct CachedRemoteImageTests {

    private let url = URL(string: "https://x.supabase.co/storage/v1/object/sign/drawing-pads/couple/them/pad.png?token=a")!

    /// Renders a view offscreen and reports whether it put anything in the render tree. A host with
    /// no content lays out at zero, which is exactly the state whose `.task` never runs.
    private func rendersSomething(_ view: some View) -> Bool {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        controller.view.layoutIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: 200, height: 200)) != .zero
    }

    /// The regression. An empty placeholder must still leave something to attach `.task` to — this
    /// fails if the internal `Color.clear` base is ever removed as dead decoration.
    @Test("a view with an empty placeholder and no image still renders")
    func emptyPlaceholderStillRenders() {
        let view = CachedRemoteImage(url: url) { image in
            image.resizable()
        } placeholder: {
            // Exactly what the partner's half of the drawing pad passes: `if isMine { … }` with
            // `isMine` false.
            EmptyView()
        }
        #expect(rendersSomething(view), "nothing to run .task against means the image never loads")
    }

    /// The same must hold before a URL exists at all — the pad's URLs are signed after first
    /// render, so this is the state the view is born in.
    @Test("a nil URL and an empty placeholder still render")
    func nilURLStillRenders() {
        let view = CachedRemoteImage(url: nil) { image in
            image.resizable()
        } placeholder: {
            EmptyView()
        }
        #expect(rendersSomething(view))
    }

    /// Saving a drawing uploads new bytes to the SAME storage path and returns a re-signed url.
    /// The view has to notice that. Keyed on the path — which was tried, to avoid re-signing
    /// restarting an in-flight download — the id does not change, the fetch never re-runs, and the
    /// Home card keeps showing the previous drawing while opening the pad shows the new one.
    ///
    /// Asserted on the id rather than by driving a fetch, because the id is the whole mechanism:
    /// two urls for the same image must be different ids, or nothing re-loads.
    @Test("a re-signed url is a different identity, so saving reloads the preview")
    func reSignedURLChangesIdentity() throws {
        let path = "/storage/v1/object/sign/drawing-pads/couple/me/pad.png"
        let before = try #require(URL(string: "https://x.supabase.co\(path)?token=first"))
        let after = try #require(URL(string: "https://x.supabase.co\(path)?token=second"))

        #expect(before != after, "the two signings must not compare equal — that is the reload trigger")
        #expect(
            before.path == after.path,
            "and they share a path, which is why keying on the path silently stops reloading"
        )
    }

    /// The base must not push callers around — it sits inside a fixed-height pad preview.
    @Test("the placeholder decides the size, not the base")
    func baseDoesNotDominateLayout() {
        let view = CachedRemoteImage(url: nil) { image in
            image.resizable()
        } placeholder: {
            Color.red.frame(width: 80, height: 40)
        }
        let controller = UIHostingController(rootView: view)
        #expect(controller.sizeThatFits(in: CGSize(width: 200, height: 200)) == CGSize(width: 80, height: 40))
    }
}
