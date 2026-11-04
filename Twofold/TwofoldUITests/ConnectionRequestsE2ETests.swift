//
//  ConnectionRequestsE2ETests.swift
//  TwofoldUITests
//
//  Answering a connection request from Settings, with the other person a real account on the
//  local stack.
//
//    ONB-10    Accept on the Settings card was a different decision from Accept on the review
//              screen: it never asked a returning couple whether to bring their history back.
//    Decline   Declining answered the request at once, from a button sitting beside Accept, with
//              nothing to say what it does or a way to take the tap back.
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
        await fulfillment(of: [enabled], timeout: 15)
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

    /// The status of every request between these two, as the server has it.
    private func requestStatuses(from requester: TestAccount, to inviter: TestAccount) async throws -> [String] {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/connection_requests",
            query: [
                URLQueryItem(name: "requester_id", value: "eq.\(requester.id)"),
                URLQueryItem(name: "inviter_id", value: "eq.\(inviter.id)"),
                URLQueryItem(name: "select", value: "status"),
            ],
            as: .service
        ) as? [[String: Any]] ?? []
        return rows.compactMap { $0["status"] as? String }
    }

    @MainActor
    func testDecliningAsksFirst() async throws {
        let me = try await Scenario.solo(name: "Sam")
        let alex = try await Scenario.makeAccount(firstName: "Alex")
        try await Scenario.completeOnboarding(alex)
        let code = try await Scenario.inviteCode(from: me.me)
        try await Scenario.requestToConnect(redeemer: alex, code: code)

        let app = launch(me)
        openSettings(app)
        require(app.buttons["Connect with your partner"], timeout: 10, "No partner row in Settings").tap()
        require(app.buttons["Review Alex's request"], timeout: 20, "The request is not on the Settings card").tap()
        require(app.buttons["Decline"], timeout: 10, "The card did not open the review screen").tap()

        require(app.staticTexts["Decline Alex's request?"], timeout: 5, "Declining did not ask first")
        capture(app, "Decline confirmation")
        let stillPending = try await requestStatuses(from: alex, to: me.me)
        XCTAssertEqual(stillPending, ["pending"], "The request was answered before the decline was confirmed")

        // Taking it back leaves the request as it was, on the same screen. The dialog's Cancel is
        // a button on some layouts and a tap outside it on others.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        _ = app.staticTexts["Decline Alex's request?"].waitForNonExistence(timeout: 5)
        require(app.buttons["Accept"], timeout: 5, "Cancelling the decline left the review screen")

        app.buttons["Decline"].tap()
        require(app.buttons["Decline request"], timeout: 5, "No way to confirm the decline").tap()
        for _ in 0..<20 {
            if try await requestStatuses(from: alex, to: me.me) == ["declined"] { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let declined = try await requestStatuses(from: alex, to: me.me)
        XCTAssertEqual(declined, ["declined"], "Confirming did not decline the request")
    }
}
