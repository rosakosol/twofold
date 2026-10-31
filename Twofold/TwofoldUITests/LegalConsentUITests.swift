//
//  LegalConsentUITests.swift
//  TwofoldUITests
//
//  The age-and-agreement gate in front of account creation, driven rather than eyeballed.
//
//  Three things are worth holding still here, and none of them is the wording:
//
//    1. That the gate actually gates. A checkbox that renders but disables nothing is worse than
//       no checkbox, because it looks like consent was collected.
//    2. That Sign in with Apple and Google are gated too. They create an account when there isn't
//       one, which is the easiest thing to forget on a screen called "sign in".
//    3. That the links open inside the app. They are markdown `legal://` URLs caught by an
//       `OpenURLAction`; if that interception ever breaks, the failure is silent — the link simply
//       does nothing, or worse, leaves the app mid-signup.
//
//  Reaching these screens uses `-onboardingStep`, a DEBUG-only launch argument (see
//  `OnboardingModel.init`). Without it `saveAccount` is nineteen screens and a dozen text fields
//  deep, and `createAccount` sits behind a live invite code.
//
//  Launched through the end-to-end harness, signed out, against the local stack. These used to
//  launch whatever the simulator held, against production, and a signed-out cold launch there sat
//  on the splash for one to two minutes — the first waits were 300s to survive it. Signed out on a
//  clean device and a local backend, the first screen is up in seconds, so the first wait is 60s:
//  still generous for a cold launch, no longer long enough to hide one that has hung.
//

import XCTest

final class LegalConsentUITests: E2ETestCase {

    @MainActor
    private func launch(at step: String) -> XCUIApplication {
        launchSignedOut(arguments: ["-onboardingStep", step])
    }

    // MARK: - The checkbox gates everything on the screen

    @MainActor
    func testProviderButtonsAreDisabledUntilTheBoxIsTicked() throws {
        let app = launch(at: "saveAccount")

        // A switch, not a button: `LegalConsentCheckbox` carries the toggle trait.
        let consent = app.switches["I'm 16 or over, and I agree to the Terms of Use and Privacy Policy"]
        XCTAssertTrue(consent.waitForExistence(timeout: 60), "Never reached Save Account, or the consent box isn't there")
        capture(app, "SaveAccount - consent not yet given")

        let apple = app.buttons["Continue with Apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5), "No Apple button to check")
        XCTAssertFalse(apple.isEnabled, "Sign in with Apple is tappable before the box is ticked — it creates an account, so it must not be")

        consent.tap()
        XCTAssertTrue(apple.isEnabled, "Ticking the box did not enable Sign in with Apple")
        capture(app, "SaveAccount - consent given")

        consent.tap()
        XCTAssertFalse(apple.isEnabled, "Un-ticking the box did not disable Sign in with Apple again")
    }

    // MARK: - The links open in-app

    @MainActor
    func testTermsLinkOpensInsideTheApp() throws {
        let app = launch(at: "saveAccount")

        let link = app.links["Terms of Use"]
        XCTAssertTrue(link.waitForExistence(timeout: 60), "No tappable Terms of Use link in the consent sentence")
        link.tap()

        // SFSafariViewController presents with a Done button; a link that escaped to Safari would
        // background the app instead, and this would time out.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Terms link did not open an in-app browser")
        XCTAssertEqual(app.state, .runningForeground, "The app left the foreground — the link went to Safari")
        capture(app, "Terms of Use - in-app sheet")
        done.tap()
    }

    @MainActor
    func testPrivacyLinkOpensInsideTheApp() throws {
        let app = launch(at: "saveAccount")

        let link = app.links["Privacy Policy"]
        XCTAssertTrue(link.waitForExistence(timeout: 60), "No tappable Privacy Policy link in the consent sentence")
        link.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Privacy link did not open an in-app browser")
        XCTAssertEqual(app.state, .runningForeground, "The app left the foreground — the link went to Safari")
        capture(app, "Privacy Policy - in-app sheet")
        done.tap()
    }

    // MARK: - The invite-path screen carries the same gate

    @MainActor
    func testCreateAccountCarriesTheSameGate() throws {
        let app = launch(at: "createAccount")

        // A switch, not a button: `LegalConsentCheckbox` carries the toggle trait.
        let consent = app.switches["I'm 16 or over, and I agree to the Terms of Use and Privacy Policy"]
        XCTAssertTrue(consent.waitForExistence(timeout: 60), "Create Account has no consent box")
        capture(app, "CreateAccount - consent not yet given")

        let apple = app.buttons["Continue with Apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertFalse(apple.isEnabled, "Sign in with Apple is tappable before the box is ticked")

        consent.tap()
        XCTAssertTrue(apple.isEnabled, "Ticking the box did not enable Sign in with Apple")
        capture(app, "CreateAccount - consent given")
    }

    // MARK: - Sign-in carries the notice, and no gate

    @MainActor
    func testSignInShowsTheNoticeWithoutGatingAnything() throws {
        let app = launchSignedOut()

        let entry = app.buttons["I have an account or invite"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "Never reached the welcome screen")
        entry.tap()

        let notice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] '16 or over'")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "Sign In is missing the age and agreement notice")
        capture(app, "SignIn - passive notice")

        // Deliberately ungated: this screen's email path cannot create an account.
        let apple = app.buttons["Sign in with Apple"]
        if apple.waitForExistence(timeout: 5) {
            XCTAssertTrue(apple.isEnabled, "Sign In's provider buttons should not be gated — the notice is sign-in-wrap, not a checkbox")
        }
    }
}
