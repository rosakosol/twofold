//
//  DailyCountdownRangeTests.swift
//  TwofoldTests
//
//  The daily card's countdown range, which the system's timer text counts down through.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Daily countdown range")
struct DailyCountdownRangeTests {
    @Test("Runs from now to the reset")
    func ahead() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(5 * 3600)
        #expect(DailyActivityCard.countdownRange(now: now, until: reset) == now..<reset)
    }

    @Test("Is empty, rather than a trap, once the reset has passed and before the next fetch")
    func passed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(-3)
        let range = DailyActivityCard.countdownRange(now: now, until: reset)
        #expect(range.isEmpty)
        #expect(range.upperBound == reset)
    }

    @Test("A new boundary from the next fetch starts a new countdown")
    func rollsOver() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let next = now.addingTimeInterval(86_400)
        #expect(DailyActivityCard.countdownRange(now: now, until: next).upperBound == next)
    }
}
