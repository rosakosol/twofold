//
//  HomeE2ETests.swift
//  TwofoldUITests
//
//  Signing in as one half of a real couple and landing on their Home.
//
//  The partner's name is the assertion because it is the one thing on Home that only a correctly
//  loaded couple can produce: before `fetchCoupleState` lands, `partner` is a placeholder, and a
//  launch that took the solo or onboarding path would never replace it.
//

import XCTest

final class HomeE2ETests: E2ETestCase {

    @MainActor
    func testPairedPlusUserLandsOnHomeShowingTheirPartner() async throws {
        let scenario = try await Scenario.pairedPlus()
        let partnerName = scenario.partner!.firstName
        let app = launch(scenario)
        // `waitForSignedInApp` clears the "You're connected" sheet, which names the partner too —
        // so the name asserted on below is Home's own, not the celebration's.
        waitForSignedInApp(app)

        XCTAssertTrue(app.buttons["Home"].isSelected, "Signed in, but not on Home")
        // The couple's avatars at the top of Home, labelled with both names.
        let header = app.descendants(matching: .any)["\(scenario.me.firstName) and \(partnerName)"]
        require(header, timeout: 20, "Home's header never named the couple as \(scenario.me.firstName) and \(partnerName)")
        capture(app, "Home - paired Plus")
    }
}
