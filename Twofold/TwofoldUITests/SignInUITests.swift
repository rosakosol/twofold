//
//  SignInUITests.swift
//  TwofoldUITests
//
//  Gets a simulator into the signed-in state the rest of this suite requires.
//
//  Every other UI test here starts with "requires a simulator that is already signed in" and skips
//  when it isn't — but nothing could put it in that state, so restoring it meant driving ~25
//  onboarding screens by hand. This does it in one step, and doubles as the only automated check
//  that email sign-in still works at all.
//
//  Credentials come from the environment, never from this file — the same rule
//  `scripts/seed-test-couple.py` follows, and for the same reason. They need the `TEST_RUNNER_`
//  prefix: a UI test's code runs in a runner app on the simulator, not on the Mac, so it inherits
//  nothing from the shell except what xcodebuild forwards under that prefix. Without it this skips,
//  which looks exactly like not having set them at all:
//
//      TEST_RUNNER_TWOFOLD_A_EMAIL=... TEST_RUNNER_TWOFOLD_A_PASSWORD=... \
//        xcodebuild test -only-testing:TwofoldUITests/SignInUITests ...
//
//  Skips rather than fails when they aren't set, so a plain full-suite run doesn't go red on a
//  machine that has no test account configured.
//

import XCTest

final class SignInUITests: XCTestCase {

    @MainActor
    func testSigningInWithEmailReachesTheSignedInApp() throws {
        let email = ProcessInfo.processInfo.environment["TWOFOLD_A_EMAIL"] ?? ""
        let password = ProcessInfo.processInfo.environment["TWOFOLD_A_PASSWORD"] ?? ""
        try XCTSkipIf(
            email.isEmpty || password.isEmpty,
            "Set TWOFOLD_A_EMAIL and TWOFOLD_A_PASSWORD to run this."
        )

        let app = XCUIApplication()
        app.launch()

        if app.buttons["Home"].waitForExistence(timeout: 10) {
            return // Already signed in — nothing to do.
        }

        let signInEntry = app.buttons["I have an account or invite"]
        XCTAssertTrue(signInEntry.waitForExistence(timeout: 30), "Never reached the welcome screen")
        signInEntry.tap()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "No email field on the sign-in sheet")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["Sign In"].tap()

        // Generous: this is a real backend round trip followed by the full couple-state fetch.
        XCTAssertTrue(
            app.buttons["Home"].waitForExistence(timeout: 60),
            "Signed in but never reached the tab bar"
        )
    }
}
