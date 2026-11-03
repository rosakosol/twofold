//
//  PanelContentHeightTests.swift
//  TwofoldTests
//
//  The Travel panel's peek height is measured from its content, and at accessibility text sizes it
//  cut its own trip and flight cards short: "Melbourne t…", "Departs in 19d…".
//
//  The measurement was taken inside the panel, which is only as tall as the last measurement made
//  it. Content taller than that was laid out squeezed into it — the text truncated to fit — and the
//  squeezed height is what got reported back. So the panel could shrink to its content but never
//  grow to it: the first height it was given (a fallback sized for the default text size) was a
//  ceiling it never got past.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct PanelContentHeightTests {

    /// A paragraph `words` words long, measured from inside a box only `box` points tall. Text is
    /// what the cards are made of, and like them it truncates rather than overflowing when it is
    /// offered less height than it needs.
    private func reportedHeight(words: Int, inBoxOf box: CGFloat) async -> CGFloat? {
        await WindowPresentationTestLock.withExclusiveWindow { () -> CGFloat? in
            var reported: CGFloat?
            let content = Text(Array(repeating: "Melbourne", count: words).joined(separator: " "))
                .font(.body)
                .onContentHeightChange { reported = $0 }
                .frame(width: 300, height: box, alignment: .top)

            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                Issue.record("no window scene to host the panel in")
                return nil
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = UIHostingController(rootView: content)
            window.isHidden = false
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            for _ in 0..<40 where reported == nil {
                try? await Task.sleep(for: .milliseconds(25))
            }
            window.isHidden = true
            return reported
        }
    }

    @Test("content taller than the panel reports the height it needs, not the panel's")
    func reportsNeededHeightWhenSqueezed() async throws {
        // About 40 lines at 300pt wide, in a box with room for about 9.
        let reported = try #require(await reportedHeight(words: 120, inBoxOf: 200))
        #expect(reported > 400, "reported \(reported)pt from a 200pt box")
    }

    @Test("content shorter than the panel reports its own height")
    func reportsOwnHeightWhenRoomy() async throws {
        let reported = try #require(await reportedHeight(words: 3, inBoxOf: 300))
        #expect(reported > 0 && reported < 60, "reported \(reported)pt")
    }
}
