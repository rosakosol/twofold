//
//  WordGuessKeyboardWidthTests.swift
//  TwofoldTests
//
//  DUO-9: the Word Guess keyboard took its key width from whatever width it was given, with no
//  ceiling. On a phone that is the right thing. On iPhone Duo's inner display (about 900pt wide
//  opened like a book) it made keys about 86pt wide with 53pt letters: a giant keyboard under a
//  board that had shrunk to fit above it.
//

import Testing
import CoreGraphics
@testable import Twofold

@MainActor
struct WordGuessKeyboardWidthTests {

    /// What a key is on a 402pt phone today (the keyboard gets the width less 8pt each side).
    private static let phoneKeyboardWidth: CGFloat = 386

    @Test func aPhoneKeepsTheKeysItHas() {
        let unit = WordGuessKeyboardView.keyUnit(forWidth: Self.phoneKeyboardWidth)
        #expect(abs(unit - 35) < 0.01)
        #expect(abs(WordGuessKeyboardView.glyphSize(forKeyWidth: unit) - 21.7) < 0.01)
    }

    @Test func theInnerDisplayDoesNotGetGiantKeys() {
        let unit = WordGuessKeyboardView.keyUnit(forWidth: 900)
        // No wider than the keys of a keyboard `Theme.Layout.columnMaxWidth` across.
        #expect(unit <= WordGuessKeyboardView.keyUnit(forWidth: Theme.Layout.columnMaxWidth) + 0.01)
        #expect(unit < 50)
    }

    @Test func lettersStopGrowingPastAKeySize() {
        #expect(WordGuessKeyboardView.glyphSize(forKeyWidth: 86) <= 30)
        #expect(WordGuessKeyboardView.glyphSize(forKeyWidth: 10) == 13)
    }
}
