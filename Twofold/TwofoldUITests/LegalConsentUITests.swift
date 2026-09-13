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
//  The first wait in each test is very generous. A signed-out cold launch sat on the splash for
//  one to two minutes on the simulator these were written against, and the 30s the rest of the
//  suite uses timed out repeatedly against screens that were on their way — twice, misleadingly,
//  reading as "the consent box isn't there" when a screenshot showed it plainly was. The later
//  waits stay short: by then the app is up, and a long timeout there would only slow a real
//  failure down.
//
//  That launch time is worth treating as a bug in its own right rather than a fact of life. These
//  tests will be slow until it is.
//

import XCTest

final class LegalConsentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(at step: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingStep", step]
        app.launch()
        return app
    }

    /// Attaches a screenshot so a failure is diagnosable and a pass is reviewable by eye.
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The checkbox gates everything on the screen

    @MainActor
    func testProviderButtonsAreDisabledUntilTheBoxIsTicked() throws {
        let app = launch(at: "saveAccount")

        let consent = app.buttons["I'm 16 or over, and I agree to the Terms of Use and Privacy Policy"]
        XCTAssertTrue(consent.waitForExistence(timeout: 300), "Never reached Save Account, or the consent box isn't there")
        capture(app, "SaveAccount - consent not yet given")

        let apple = app.buttons["Sign in with Apple"]
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
        XCTAssertTrue(link.waitForExistence(timeout: 300), "No tappable Terms of Use link in the consent sentence")
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
        XCTAssertTrue(link.waitForExistence(timeout: 300), "No tappable Privacy Policy link in the consent sentence")
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

        let consent = app.buttons["I'm 16 or over, and I agree to the Terms of Use and Privacy Policy"]
        XCTAssertTrue(consent.waitForExistence(timeout: 300), "Create Account has no consent box")
        capture(app, "CreateAccount - consent not yet given")

        let apple = app.buttons["Sign in with Apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertFalse(apple.isEnabled, "Sign in with Apple is tappable before the box is ticked")

        consent.tap()
        XCTAssertTrue(apple.isEnabled, "Ticking the box did not enable Sign in with Apple")
        capture(app, "CreateAccount - consent given")
    }

    // MARK: - Sign-in carries the notice, and no gate

    @MainActor
    func testSignInShowsTheNoticeWithoutGatingAnything() throws {
        let app = XCUIApplication()
        app.launch()

        let entry = app.buttons["I have an account or invite"]
        XCTAssertTrue(entry.waitForExistence(timeout: 300), "Never reached the welcome screen — is this simulator signed in?")
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
