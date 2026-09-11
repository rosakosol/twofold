//
//  LocalizedStringResourceTestSupport.swift
//  TwofoldTests
//
//  Resolving a `LocalizedStringResource` so a test can assert on the words.
//
//  User-facing sentences return `LocalizedStringResource` rather than `String` — see
//  `SudokuComparison.verdict` — so `Text` localises them and Xcode's extractor can find them. That
//  is the right type to return and the wrong one to compare against a literal, which is all this
//  bridges.
//
//  Tests run in the app's development language, so what comes back is the key with its values
//  filled in: the exact English the user sees today, which is what these assertions are about.
//

import Foundation
@testable import Twofold

extension LocalizedStringResource {
    /// The resolved string, for assertions.
    var resolved: String { String(localized: self) }
}
