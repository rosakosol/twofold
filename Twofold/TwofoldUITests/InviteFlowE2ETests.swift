//
//  InviteFlowE2ETests.swift
//  TwofoldUITests
//
//  Two people, one invite: the routes an invitee takes into Twofold, each against a real inviter
//  on the local stack.
//
//    ONB-1   An invite link that cold-launched the app was dropped for anyone signed out.
//    ONB-2   An invite link opened by somebody signed in but still onboarding sent them to
//            "Create account" again.
//    ONB-3   A typed code was not checked until an account had been made for it, and its
//            headline never named the inviter.
//    ONB-5   Once the account existed, Back led to the sign-up screens again.
//    ONB-13  Killing the app part-way through the invitee flow resumed it as the inviter's.
//
//  A cold launch from Messages cannot be driven from here: the system would launch the app
//  without the test's environment, pointed at production. `TWOFOLD_E2E_HOLD_LAUNCH` holds the
//  launch on its loading screen instead, and the link is opened into it — the same state a cold
//  launch leaves the app in when the link arrives. A real tap in Messages on a device is still
//  worth doing by hand; see the batch report.
//

import XCTest

final class InviteFlowE2ETests: E2ETestCase {

    private func inviteURL(_ code: String) -> URL {
        // The legacy scheme rather than the universal link: a universal link opened on the
        // simulator goes to Safari unless the site's association has been fetched. Both reach the
        // same handler, through `InviteCode.code(from:)`.
        URL(string: "twofold://invite/\(code)")!
    }

    private func invitedHeadline(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "\(name) invited you")).firstMatch
    }

    /// Types into `field` once it has focus. Tapped every time, because the keyboard staying up
    /// from the previous field says nothing about which one has it; and retried, because a field in
    /// a sheet does not take focus from a tap made while the sheet is still sliding in.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2),
               (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                break
            }
        }
        field.typeText(text)
    }

    /// One letter at a time. The code field reformats itself on every change (`InviteCode
    /// .autoFormat`), and typed at full speed a keystroke landing mid-reformat was dropped.
    private func typeCode(_ code: String, into field: XCUIElement, in app: XCUIApplication) {
        type("", into: field, in: app)
        for letter in code where letter.isLetter {
            field.typeText(String(letter))
            usleep(150_000)
        }
    }

    /// Welcome → "I have an account or invite" → "Have an invite code instead?"
    @MainActor
    private func openTypedCodeScreen(_ app: XCUIApplication) {
        waitForWelcome(app)
        app.buttons["I have an account or invite"].tap()
        require(app.buttons["Have an invite code instead?"], timeout: 10, "No invite-code route on the sign-in sheet").tap()
        require(app.staticTexts["Enter your partner's code"], timeout: 10, "Never reached the code screen")
    }

    // MARK: - ONB-1

    @MainActor
    func testInviteLinkOpenedWhileTheAppIsLaunchingReachesTheInvite() async throws {
        let inviter = try await Scenario.solo(name: "Max")
        let code = try await Scenario.inviteCode(from: inviter.me)

        let app = launch(nil, environment: ["TWOFOLD_E2E_HOLD_LAUNCH": "8"])
        // Still on the loading screen: the link meets the app as a cold launch would.
        sleep(2)
        app.open(inviteURL(code))

        require(invitedHeadline("Max", in: app), timeout: 40, "A link that arrived during launch was dropped")
        XCTAssertTrue(app.buttons["Join Twofold"].exists)
        XCTAssertFalse(app.buttons["I have an account or invite"].exists, "Landed on Welcome rather than the invite")
        capture(app, "Invite from a link opened during launch")
    }

    // MARK: - ONB-2

    @MainActor
    func testInviteLinkWhileOnboardingSignedInOffersToConnectNotToSignUp() async throws {
        let inviter = try await Scenario.solo(name: "Max")
        let code = try await Scenario.inviteCode(from: inviter.me)
        let me = try await Scenario.midOnboarding(name: "Sam")

        let app = launch(me)
        require(app.staticTexts["Which sounds most like you two?"], timeout: 60, "A signed-in account with onboarding unfinished should open on its first question")
        dismissSystemAlerts()

        app.open(inviteURL(code))

        require(app.staticTexts["Connect with Max"], timeout: 20, "The invite did not offer to connect this account")
        XCTAssertFalse(app.buttons["Join Twofold"].exists, "Sent to the sign-up flow while already signed in")
        capture(app, "Redeem sheet over onboarding")

        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5) && connect.isEnabled)
        connect.tap()

        // A tapped link pairs straight away, so the sheet closes with no "request sent".
        _ = app.staticTexts["Connect with Max"].waitForNonExistence(timeout: 20)
        let couple = try await Scenario.activeCouple(between: me.me, and: inviter.me)
        XCTAssertNotNil(couple, "Connecting from the link did not pair the account that was already signed in")
    }

    // MARK: - ONB-3

    @MainActor
    func testTypedCodeIsCheckedBeforeAnyAccountAndNamesTheInviter() async throws {
        let inviter = try await Scenario.solo(name: "Max")
        let code = try await Scenario.inviteCode(from: inviter.me)

        let app = launchSignedOut()
        openTypedCodeScreen(app)

        let field = app.textFields["e.g. ABCD-EFGH"]
        typeCode("ZZZZZZZZ", into: field, in: app)
        app.buttons["Continue"].tap()
        require(app.staticTexts["We couldn't find that code — check it with your partner."], timeout: 15, "A code nobody issued was not turned away")
        XCTAssertFalse(app.buttons["Join Twofold"].exists, "Moved on with a code that does not exist")
        capture(app, "Wrong code refused")

        field.doubleTap()
        for _ in 0..<12 { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        typeCode(code, into: field, in: app)
        app.buttons["Continue"].tap()

        require(invitedHeadline("Max", in: app), timeout: 15, "The typed code's invite does not name the inviter")
        capture(app, "Typed code names the inviter")
    }

    // MARK: - ONB-5, ONB-13

    /// The whole typed-code invitee flow, signing up through the screens: account, then no way
    /// back to it, then a kill part-way through and a resume that carries on as the invitee.
    @MainActor
    func testInviteeSignupCannotGoBackAndResumesAsTheInvitee() async throws {
        let inviter = try await Scenario.solo(name: "Max")
        let code = try await Scenario.inviteCode(from: inviter.me)
        let email = "e2e-invitee-\(UUID().uuidString.prefix(8).lowercased())@e2e.twofold.test"
        let password = "e2e-\(UUID().uuidString)"

        let app = launchSignedOut()
        openTypedCodeScreen(app)
        typeCode(code, into: app.textFields["e.g. ABCD-EFGH"], in: app)
        app.buttons["Continue"].tap()
        require(app.buttons["Join Twofold"], timeout: 15, "Never reached the invite").tap()

        require(app.textFields["First name"], timeout: 10, "Never reached Create account")
        type("Rae", into: app.textFields["First name"], in: app)
        type(email, into: app.textFields["Email"], in: app)
        // Secure fields once each: a secure field that loses focus and gets it back clears itself
        // on the next keystroke, so the retrying `type` would empty it.
        for name in ["Password", "Confirm password"] {
            let field = app.secureTextFields[name]
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            field.typeText(password)
        }
        // The keyboard covers the consent box.
        app.staticTexts["Create your Twofold account"].tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        app.switches["I'm 16 or over, and I agree to the Terms of Use and Privacy Policy"].tap()
        let continueButton = app.buttons["Continue"]
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: continueButton)
        await fulfillment(of: [enabled], timeout: 5)
        continueButton.tap()

        require(app.staticTexts["Where are you based?"], timeout: 30, "Creating the account did not move on to Home City")
        dismissSystemAlerts()
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists, "Home City still has a way back to the sign-up form")
        app.swipeRight()
        XCTAssertFalse(app.textFields["First name"].waitForExistence(timeout: 2), "A back-swipe reached the sign-up form again")
        capture(app, "Home City, nothing behind it")

        let created = try await Scenario.profile(email: email)
        XCTAssertFalse((created?["onboarding_account_created_at"] as? String ?? "").isEmpty, "The invitee's account was not recorded as made by onboarding")

        app.buttons["Continue"].tap()
        require(app.staticTexts["Customise your photo"], timeout: 30, "Continue on Home City did not redeem and move on")

        // Killed here. The request exists; what is left of the flow is the invitee's.
        app.terminate()
        let relaunched = launch(nil, keepDevice: true)
        require(relaunched.staticTexts["Your request to connect with Max"], timeout: 60, "Relaunch did not offer to resume as the invitee")
        capture(relaunched, "Resume, as the invitee")
        relaunched.buttons["Pick up where you left off"].tap()

        require(relaunched.staticTexts["Customise your photo"], timeout: 15, "Resuming did not carry on with the invitee's own flow")
        XCTAssertFalse(relaunched.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Connect with'")).firstMatch.exists, "Resumed into the inviter's invite screen")
        relaunched.buttons["Continue"].tap()
        require(relaunched.staticTexts["Request sent"], timeout: 15, "The resumed flow lost the request")
    }
}
