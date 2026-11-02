//
//  ConnectionRequestsE2ETests.swift
//  TwofoldUITests
//
//  Answering a connection request from Settings, with the other person a real account on the
//  local stack.
//
//    ONB-10    Accept on the Settings card was a different decision from Accept on the review
//              screen: it never asked a returning couple whether to bring their history back.
//

import XCTest

final class ConnectionRequestsE2ETests: E2ETestCase {

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        waitForSignedInApp(app)
        require(app.buttons["Settings"], timeout: 10, "No Settings button on Home").tap()
    }

    @MainActor
    func testAcceptingFromSettingsOffersToBringHistoryBack() async throws {
        // Paired, with something shared, then the partner leaves: an archive both can restore.
        let couple = try await Scenario.paired(tier: .plus, myName: "Sam", partnerName: "Alex")
        try await couple.addMemory(title: "Where we met")
        try await couple.partnerLeaves()
        let partner = try XCTUnwrap(couple.partner)
        // And asks to come back, by typing Sam's new code.
        let code = try await Scenario.inviteCode(from: couple.me)
        try await Scenario.requestToConnect(redeemer: partner, code: code)

        let app = launch(couple)
        openSettings(app)
        require(app.buttons["Connect with your partner"], timeout: 10, "No partner row in Settings").tap()

        require(app.buttons["Review Alex's request"], timeout: 20, "The request is not on the Settings card").tap()
        let accept = require(app.buttons["Accept"], timeout: 10, "The card did not open the review screen")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: accept)
        wait(for: [enabled], timeout: 15)
        accept.tap()

        require(app.staticTexts["You have history with Alex"], timeout: 10, "Accepting from Settings did not offer to bring the archive back")
        capture(app, "Restore choice from Settings")
        app.buttons["Bring it back"].tap()

        for _ in 0..<20 {
            if try await Scenario.activeCouple(between: couple.me, and: partner) != nil { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let restored = try await Scenario.activeCouple(between: couple.me, and: partner)
        XCTAssertEqual(restored, couple.coupleID, "Bringing it back did not reopen the couple they had")
    }
}
