//
//  CopyFixesTests.swift
//  TwofoldTests
//
//  Words that were wrong for the person reading them: a plural (HOME-16).
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct CopyFixesTests {

    // MARK: HOME-16

    @Test("one day to go is singular")
    func oneDayToGo() {
        let days = 1
        #expect(String(localized: "\(days) days to go") == "1 day to go")
    }

    @Test("several days to go stays plural")
    func severalDaysToGo() {
        let days = 12
        #expect(String(localized: "\(days) days to go") == "12 days to go")
    }
}
