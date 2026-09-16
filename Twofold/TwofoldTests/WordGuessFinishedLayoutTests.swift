//
//  WordGuessFinishedLayoutTests.swift
//  TwofoldTests
//
//  The finished board has to share the screen with the card that reports the result — and, when
//  the two of them can't both have what they want, give way rather than push the card's one action
//  below the fold.
//
//  That was the bug: the board took its size from the screen's width alone, so on a 402pt phone it
//  came to ~445pt of the ~737pt available and the "Send Reminder" button ended up just off-screen.
//  Compressing the card fixed the phone it was reported on; this is the other half, and it is the
//  half that has to hold on a small screen or at a large text size.
//
//  Tested here rather than on a simulator because the interesting cases are the cramped ones, which
//  are tedious to stage on a device and are pure arithmetic in any case.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Word Guess finished layout")
struct WordGuessFinishedLayoutTests {

    /// Board, card, and the padding between and around them.
    private func totalHeight(tileSide: CGFloat, cardHeight: CGFloat) -> CGFloat {
        WordGuessBoardView.boardHeight(forTileSide: tileSide) + cardHeight + Theme.Spacing.md * 3
    }

    @Test("A roomy screen leaves the board at its full width-derived size")
    func roomyScreenKeepsFullBoard() {
        // iPhone 17 Pro, less the navigation bar and safe areas.
        let width: CGFloat = 402
        let height: CGFloat = 737
        let card: CGFloat = 190

        let side = WordGuessGameView.finishedTileSide(width: width, height: height, cardHeight: card)

        #expect(side == WordGuessBoardView.tileSide(forWidth: width - Theme.Spacing.md * 2))
        #expect(totalHeight(tileSide: side, cardHeight: card) <= height)
    }

    @Test("A small screen shrinks the board rather than pushing the card off it")
    func smallScreenShrinksBoard() {
        // iPhone SE, less the navigation bar and safe areas.
        let width: CGFloat = 375
        let height: CGFloat = 603
        // The waiting card plus the Send Reminder button below it.
        let card: CGFloat = 190

        let side = WordGuessGameView.finishedTileSide(width: width, height: height, cardHeight: card)

        #expect(side < WordGuessBoardView.tileSide(forWidth: width - Theme.Spacing.md * 2))
        #expect(totalHeight(tileSide: side, cardHeight: card) <= height)
    }

    @Test("A large text size shrinks it further, and still fits")
    func largeTextStillFits() {
        let width: CGFloat = 402
        let height: CGFloat = 737
        // Every line of the card wrapping at an accessibility size.
        let card: CGFloat = 360

        let side = WordGuessGameView.finishedTileSide(width: width, height: height, cardHeight: card)

        #expect(totalHeight(tileSide: side, cardHeight: card) <= height)
    }

    @Test("Past the floor it stops shrinking and lets the screen scroll instead")
    func absurdCardHitsTheFloor() {
        // `WordGuessComparisonView` with both results, or an accessibility size on a small phone —
        // no tile size makes this fit, and a board crushed to nothing is worse than a scroll.
        let side = WordGuessGameView.finishedTileSide(width: 375, height: 603, cardHeight: 560)

        #expect(side == WordGuessGameView.minFinishedTileSide)
    }

    @Test("A card measured at zero behaves exactly as the old width-only sizing did")
    func unmeasuredCardMatchesPreviousBehaviour() {
        // The first layout pass, before `onGeometryChange` has reported. It must not flash a
        // shrunken board on the way to the right one.
        let width: CGFloat = 402
        let side = WordGuessGameView.finishedTileSide(width: width, height: 737, cardHeight: 0)

        #expect(side == WordGuessBoardView.tileSide(forWidth: width - Theme.Spacing.md * 2))
    }
}
