//
//  AnniversaryE2ETests.swift
//  TwofoldUITests
//
//  A couple with no anniversary, which is now something onboarding allows.
//
//  It used to be dated to today wherever it was shown: Stats said "0 days" together, and Partner
//  setup's date picker showed today as the anniversary.
//
//  The Save test passed before the fix too — `updateAnniversaryDate` skips a date equal to the one
//  already held, so an untouched picker was never written. It stays as the guard for the nil path:
//  with no date, Save must write nothing.
//

import XCTest

final class AnniversaryE2ETests: E2ETestCase {

    @MainActor
    func testStatsAsksForTheAnniversaryRatherThanCountingFromToday() async throws {
        let couple = try await Scenario.pairedPlus()
        let app = launch(couple)
        waitForSignedInApp(app)
        capture(app, "Home with no anniversary")

        openTab("Stats", in: app)
        require(app.buttons["Add your anniversary"], timeout: 15, "Stats did not offer to add the anniversary")
        XCTAssertFalse(app.staticTexts["0 days"].exists, "Stats counted the relationship from today")
        capture(app, "Stats with no anniversary")

        app.buttons["Add your anniversary"].tap()
        require(app.navigationBars["Your partner"], timeout: 10, "Adding the anniversary did not open the screen it is set on")
    }

    @MainActor
    func testSavingPartnerSetupLeavesAnUnsetAnniversaryUnset() async throws {
        let couple = try await Scenario.pairedPlus()
        let app = launch(couple)
        waitForSignedInApp(app)
        require(app.buttons["Settings"], timeout: 10, "No Settings button on Home").tap()
        require(app.buttons["About your partner"], timeout: 10, "No partner row in Settings").tap()

        require(app.navigationBars["Your partner"], timeout: 10, "Partner setup did not open")
        capture(app, "Partner setup with no anniversary")
        require(app.buttons["Save"], timeout: 5, "No Save on Partner setup").tap()
        _ = app.navigationBars["Your partner"].waitForNonExistence(timeout: 10)

        let coupleID = try XCTUnwrap(couple.coupleID)
        let row = try await couple.row("couples", id: coupleID, columns: "started_dating_on")
        XCTAssertTrue(row?["started_dating_on"] is NSNull, "Saving wrote an anniversary nobody chose: \(String(describing: row?["started_dating_on"]))")
    }
}
