//
//  NewsreaderSizeTests.swift
//  TwofoldTests
//
//  Newsreader takes its size from the view's Dynamic Type size, not the device's (UX-11), so a
//  share card pinned to `.large` draws its wordmark the same for every sender.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

struct NewsreaderSizeTests {

    @Test("a text style at .large is the style's own size")
    func largeIsDefault() {
        let expected = UIFont.preferredFont(
            forTextStyle: .title2,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        #expect(Font.newsreaderPointSize(.title2, at: .large) == expected)
    }

    @Test("it grows with the size it is given")
    func grows() {
        #expect(Font.newsreaderPointSize(.title2, at: .accessibility3) > Font.newsreaderPointSize(.title2, at: .large))
        #expect(Font.newsreaderPointSize(.body, size: 19, at: .large) == 19)
        #expect(Font.newsreaderPointSize(.body, size: 19, at: .xxxLarge) > 19)
    }
}
