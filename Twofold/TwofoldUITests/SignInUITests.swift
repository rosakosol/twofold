//
//  SignInUITests.swift
//  TwofoldUITests
//
//  The email sign-in form, driven: a real account, its real password, typed into the sheet.
//
//  Every other end-to-end test signs in underneath the UI (`TWOFOLD_E2E_EMAIL`), because Apple and
//  Google's sheets cannot be driven and the form is not what those tests are about. This is the
//  one that is about the form, so it launches signed out and goes through it. It used to sign in
//  to production with credentials from the environment, and existed mostly to put a simulator into
//  the signed-in state the rest of the suite needed; the harness does that per test now.
//

import XCTest

final class SignInUITests: E2ETestCase {

    @MainActor
    func testSigningInWithEmailReachesTheSignedInApp() async throws {
        let scenario = try await Scenario.solo()
        let app = launchSignedOut()

        waitForWelcome(app)
        app.buttons["I have an account or invite"].tap()

        let emailField = require(app.textFields["Email"], timeout: 10, "No email field on the sign-in sheet")
        emailField.tap()
        emailField.typeText(scenario.me.email)

        let passwordField = require(app.secureTextFields["Password"], timeout: 5, "No password field")
        passwordField.tap()
        passwordField.typeText(scenario.me.password)

        app.buttons["Sign in"].tap()

        // A backend round trip followed by the full couple-state fetch.
        waitForSignedInApp(app)
    }
}
