//
//  OnboardingSignOutE2ETests.swift
//  TwofoldUITests
//
//  Leaving onboarding part-way, signed in, has to end on Welcome and stay there — ONB-4.
//
//  Somebody who made an account and closed the app comes back to onboarding's first question, as
//  its root, signed in. Its Back button signs out. That used to land back on the same question
//  (`needsOnboarding` survived the sign-out), and the coordinator's model outlived the account, so
//  the next "Get started" carried the last person's flow. The relaunch at the end is what proves
//  the session really went: a sign-out that only changed the screen would undo itself there.
//

import XCTest

final class OnboardingSignOutE2ETests: E2ETestCase {

    @MainActor
    func testSigningOutMidOnboardingReturnsToWelcomeAndStaysThere() async throws {
        let scenario = try await Scenario.midOnboarding()
        let app = launch(scenario)

        require(app.staticTexts["Which sounds most like you two?"], timeout: 60, "A signed-in account with onboarding unfinished should open on its first question")
        dismissSystemAlerts()
        capture(app, "Onboarding root, signed in")

        app.buttons["Back"].tap()
        require(app.buttons["Go back"], timeout: 5, "Back didn't ask before giving up the session").tap()

        waitForWelcome(app, timeout: 20)
        XCTAssertFalse(app.staticTexts["Which sounds most like you two?"].exists, "Signed out, but still on the onboarding question")
        capture(app, "Welcome after signing out")

        // Same device, no credentials: whatever is in the Keychain decides where this opens.
        app.terminate()
        let relaunched = launch(nil, keepDevice: true)
        waitForWelcome(relaunched)
    }
}
