//
//  NewsreaderFontTests.swift
//  TwofoldTests
//
//  The serif is a bundled font, so it can go missing in ways a system font cannot: dropped from the
//  target, renamed, or left out of UIAppFonts. `UIFont.newsreader` falls back to the system serif
//  rather than showing nothing, which also means nothing on screen would say it had gone. This does.
//

import Testing
import SwiftUI
import UIKit
import CoreText
@testable import Twofold

struct NewsreaderFontTests {
    @Test("Newsreader is bundled, registered and found")
    func loads() {
        #expect(UIFont.newsreader(size: 19).familyName == "Newsreader")
    }

    /// The weight and optical size are set on the variable font's own axes, so bold is genuinely
    /// heavier and a title gets the title cut. Core Text omits an axis left at its default, so a
    /// missing value reads as the default (400 weight, 18pt optical size).
    @Test("weight and optical size reach the font's axes")
    func axes() {
        func axis(_ font: UIFont, _ tag: Int, default value: Double) -> Double {
            (CTFontCopyVariation(font as CTFont) as? [Int: Double])?[tag] ?? value
        }
        let weight = 0x7767_6874, opticalSize = 0x6F70_737A
        #expect(axis(UIFont.newsreader(size: 44, weight: .regular), weight, default: 400) == 400)
        #expect(axis(UIFont.newsreader(size: 44, weight: .bold), weight, default: 400) == 700)
        #expect(axis(UIFont.newsreader(size: 44), opticalSize, default: 18) == 44)
        #expect(axis(UIFont.newsreader(size: 10), opticalSize, default: 18) == 10)
    }
}
