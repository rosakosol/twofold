//
//  AdaptiveLayoutTests.swift
//  TwofoldTests
//
//  The rules behind the iPhone Duo layouts (AdaptiveLayout.swift): what counts as wide enough to
//  put a game board beside its controls, and how a phone-sized fixed height grows with width. Both
//  must leave every ordinary iPhone exactly as it was.
//

import Testing
import CoreGraphics
@testable import Twofold

@MainActor
struct AdaptiveLayoutTests {

    @Test("phones held upright stay stacked")
    func phonesStayStacked() {
        #expect(!BoardArrangement.isSideBySide(CGSize(width: 402, height: 874)))  // iPhone 17 Pro
        #expect(!BoardArrangement.isSideBySide(CGSize(width: 375, height: 667)))  // iPhone SE
        #expect(!BoardArrangement.isSideBySide(CGSize(width: 466, height: 678)))  // Duo, closed
    }

    @Test("the Duo's inner display goes side by side only when opened like a book")
    func innerDisplay() {
        #expect(BoardArrangement.isSideBySide(CGSize(width: 951, height: 669)))
        #expect(!BoardArrangement.isSideBySide(CGSize(width: 669, height: 951)))
    }

    @Test("a fixed height is unchanged at phone widths")
    func phoneHeightsUnchanged() {
        for width: CGFloat in [0, 300, 358] {
            #expect(Theme.Layout.proportionalHeight(base: 260, width: width, maxScale: 1.6) == 260)
        }
    }

    @Test("a fixed height grows with width, up to its cap")
    func heightsGrowAndCap() {
        let column = Theme.Layout.proportionalHeight(base: 260, width: 451, maxScale: 1.6)
        #expect(column > 260 && column < 260 * 1.6)
        #expect(Theme.Layout.proportionalHeight(base: 260, width: 900, maxScale: 1.6) == 260 * 1.6)
    }
}
