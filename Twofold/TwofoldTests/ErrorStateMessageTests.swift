//
//  ErrorStateMessageTests.swift
//  TwofoldTests
//
//  What the shared error state says about a failed load (UX-9, GAME-8).
//
//  The game screens used to print `localizedDescription` as it came, so a dropped connection read
//  "The Internet connection appears to be offline." with nothing to do about it. No connection and
//  an unreachable server now get their own sentences; anything the app has a name for keeps the
//  wording `BackendFailure` gives it.
//

import Foundation
import Testing
@testable import Twofold

@MainActor
struct ErrorStateMessageTests {

    @Test("no connection says you're offline", arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
    ])
    func offline(code: URLError.Code) {
        #expect(ErrorStateView.message(for: URLError(code)) == "You're offline. Check your connection and try again.")
    }

    @Test("a server that can't be reached says so", arguments: [
        URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost,
    ])
    func unreachable(code: URLError.Code) {
        #expect(ErrorStateView.message(for: URLError(code)) == "Couldn't reach Twofold. Check your connection and try again.")
    }

    @Test("a refusal the app knows keeps its own wording")
    func namedRefusal() {
        let error = BackendError.wordGuessDailyLimit
        #expect(ErrorStateView.message(for: error) == BackendFailure.message(for: error))
        #expect(ErrorStateView.message(for: error) != "You're offline. Check your connection and try again.")
    }

    @Test("anything else falls back to the error's own description")
    func otherErrors() {
        struct Odd: LocalizedError { var errorDescription: String? { "Something odd" } }
        #expect(ErrorStateView.message(for: Odd()) == "Something odd")
    }
}
