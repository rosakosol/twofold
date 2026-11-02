//
//  BlockedPeopleE2ETests.swift
//  TwofoldUITests
//
//  Blocking had no way back. There was no list of who you had blocked, so the unblock the server
//  had always offered was unreachable. The blocked person is a real account on the local stack.
//

import XCTest

final class BlockedPeopleE2ETests: E2ETestCase {

    @MainActor
    func testBlockedPersonCanBeUnblockedFromSettings() async throws {
        let me = try await Scenario.solo(name: "Sam")
        let them = try await Scenario.makeAccount(firstName: "Bo")
        try await Scenario.block(them, by: me.me)

        let app = launch(me)
        waitForSignedInApp(app)
        require(app.buttons["Settings"], timeout: 10, "No Settings button on Home").tap()
        let help = require(app.buttons["Help"], timeout: 10, "No Help row in Settings")
        for _ in 0..<4 where !help.isHittable { app.swipeUp() }
        help.tap()
        require(app.buttons["Blocked people"], timeout: 10, "No Blocked people row under Help").tap()

        require(app.staticTexts["Bo"], timeout: 15, "The blocked person is not listed")
        capture(app, "Blocked people")
        app.buttons["Unblock"].firstMatch.tap()
        let confirm = app.sheets.buttons["Unblock"].exists ? app.sheets.buttons["Unblock"] : app.buttons.matching(identifier: "Unblock").element(boundBy: 1)
        require(confirm, timeout: 5, "Unblocking did not ask first").tap()

        require(app.staticTexts["No one blocked"], timeout: 15, "The list still shows them after unblocking")
        let stillBlocked = try await Scenario.isBlocked(them, by: me.me)
        XCTAssertFalse(stillBlocked, "The screen said unblocked; the server still has the block")
    }
}
