//
//  DistanceShareFitTests.swift
//  TwofoldTests
//
//  The distance card is the only thing on its share screen, and it should be seeable in one look —
//  a preview you have to scroll to judge isn't really a preview. It was in a ScrollView, and at
//  340x616 it overflowed the space available on every iPhone.
//
//  It's scaled to fit instead, which has two ways to go wrong: not shrinking enough on a small
//  screen, and shrinking a card that already fits.
//

import Testing
import SwiftUI
@testable import Twofold

@MainActor
struct DistanceShareFitTests {

    /// Measured off the real card at its design width, with both stat tiles present.
    private let cardHeight: CGFloat = 616

    /// Roughly what the GeometryReader is handed once the nav bar, the share button and the
    /// paddings have taken their share, on the shortest and tallest phones this runs on.
    private let iPhoneSE = CGSize(width: 375 - 32, height: 667 - 230)
    private let iPhone17Pro = CGSize(width: 402 - 32, height: 874 - 230)

    private func fits(_ available: CGSize) -> Bool {
        let scale = DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: available)
        return cardHeight * scale <= available.height + 0.5
            && DistanceRevealShareView.cardWidth * scale <= available.width + 0.5
    }

    @Test("the card fits the space it is given, on the smallest phone")
    func fitsOnASmallPhone() {
        #expect(fits(iPhoneSE))
    }

    @Test("the card fits on a large phone too")
    func fitsOnALargePhone() {
        #expect(fits(iPhone17Pro))
    }

    /// The negative control, and a correction to what I first assumed. The card does not overflow
    /// everywhere — at 616pt it clears a large phone's ~644pt of room and only needs shrinking on
    /// a small one. So the two tests above are exercising different branches, and it is worth
    /// saying which: the small phone proves the scaling works, the large one proves it stays out
    /// of the way.
    @Test("shrinking happens only where it is needed")
    func shrinksOnlyWhereNeeded() {
        #expect(cardHeight > iPhoneSE.height, "no shrinking needed on a small phone — this test has stopped meaning anything")
        #expect(DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: iPhoneSE) < 1)

        #expect(cardHeight <= iPhone17Pro.height)
        #expect(DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: iPhone17Pro) == 1, "a card that fits is being shrunk anyway")
    }

    /// And it is never blown up past its design size. The card is rendered at 340pt wide for
    /// export; scaling the preview beyond that would show something the exported image isn't.
    @Test("a card that already fits is left alone")
    func neverScalesUp() {
        let roomy = CGSize(width: 1000, height: 2000)
        #expect(DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: roomy) == 1)
    }

    /// Before the card has been measured, and in a zero-sized layout pass, it must render at its
    /// natural size rather than collapsing to nothing.
    @Test("an unmeasured card renders at full size")
    func unmeasuredIsFullSize() {
        #expect(DistanceRevealShareView.fittingScale(cardHeight: 0, in: iPhoneSE) == 1)
        #expect(DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: .zero) == 1)
    }

    /// Width matters as well as height — a phone narrower than the card's 340pt design width has to
    /// shrink it for that reason alone.
    @Test("a narrow screen shrinks the card too")
    func narrowScreenShrinks() {
        let narrow = CGSize(width: 300, height: 4000)
        let scale = DistanceRevealShareView.fittingScale(cardHeight: cardHeight, in: narrow)
        #expect(scale < 1)
        #expect(DistanceRevealShareView.cardWidth * scale <= narrow.width + 0.5)
    }
}
