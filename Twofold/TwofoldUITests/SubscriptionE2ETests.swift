//
//  SubscriptionE2ETests.swift
//  TwofoldUITests
//
//  What a couple sees with and without a subscription, with the server and the device agreeing.
//
//  Two groups. `SubscriptionE2ETests` runs in the default test plan and needs nothing beyond the
//  local stack: RevenueCat is left unconfigured and the device's store answer comes from
//  `TWOFOLD_E2E_TIER`. `PaywallTrialCopyE2ETests` needs real products to put a price and a trial
//  on, so it runs only under the Purchases plan (Twofold-Purchases.xctestplan), which attaches
//  Twofold.storekit and has the app configure RevenueCat anonymously. That plan does reach
//  RevenueCat's API for the offering — there is no local RevenueCat — but never as a test account.
//

import XCTest

final class SubscriptionE2ETests: E2ETestCase {

    /// A lapsed couple keeps everything they made and is told plainly why they can't add to it.
    /// The rule lives in the database (20261028000000); this is the client's half of it.
    @MainActor
    func testLapsedCoupleKeepsTheirHistoryAndIsShownWhy() async throws {
        let scenario = try await Scenario.lapsed()
        try await scenario.addMemory(title: "Gelato by the Pantheon")
        let app = launch(scenario)
        waitForSignedInApp(app)

        require(app.staticTexts["No active subscription"], timeout: 20, "A lapsed couple's Home should say there is no active subscription")
        require(app.buttons["See plans"], timeout: 5, "The no-subscription card has no way to the plans")
        capture(app, "Home - lapsed")

        openTab("Memories", in: app)
        let listMode = app.buttons["list.bullet"]
        if listMode.waitForExistence(timeout: 10) { listMode.tap() }
        require(app.staticTexts["Gelato by the Pantheon"], timeout: 20, "A lapsed couple's memory is no longer readable")
    }

    /// The other side of the same card: a paying couple never sees it.
    @MainActor
    func testPayingCoupleIsNotShownTheNoSubscriptionCard() async throws {
        let scenario = try await Scenario.paired(tier: .premium, payer: .partner)
        let app = launch(scenario)
        waitForSignedInApp(app)
        // Long enough for `checkSubscription` to have resolved — the card is held back until then.
        require(app.descendants(matching: .any)["\(scenario.me.firstName) and \(scenario.partner!.firstName)"],
                timeout: 20, "Home never loaded the couple")
        XCTAssertFalse(app.staticTexts["No active subscription"].waitForExistence(timeout: 5),
                       "A couple whose partner pays was shown 'No active subscription'")
    }
}

/// ONB-14: trial wording only for an account that would actually get the trial. Purchases plan only.
///
/// Not yet trustworthy. The never-subscribed case fails: the paywall's products load, but with no
/// introductory offer and after a sixteen-second product request, which looks like the App Store
/// sandbox answering rather than Twofold.storekit. Until the plan's StoreKit attachment is shown to
/// reach the app, the lapsed case passing proves nothing — it would pass with no trial anywhere.
final class PaywallTrialCopyE2ETests: E2ETestCase {

    @MainActor
    private func openPaywallFromHome(_ scenario: Scenario) -> XCUIApplication {
        let app = launch(scenario, storeKit: true)
        waitForSignedInApp(app)
        require(app.buttons["See plans"], timeout: 20, "No 'See plans' on an unsubscribed couple's Home").tap()
        let failed = app.staticTexts["No subscription plans are available right now."]
        let subscribe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Subscribe", "Start my")).firstMatch
        require(subscribe, timeout: 30, failed.exists
            ? "The paywall loaded no plans — is Twofold.storekit attached (run the Purchases test plan) and RevenueCat reachable?"
            : "The paywall never showed its purchase button")
        return app
    }

    /// Lapsed: Apple will not give the Plus trial a second time, so the button must not offer it.
    @MainActor
    func testLapsedCoupleIsNotOfferedATrial() async throws {
        let scenario = try await Scenario.lapsed()
        let app = openPaywallFromHome(scenario)
        capture(app, "Paywall - lapsed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "free trial")).firstMatch.exists,
                       "A lapsed subscriber was offered a free trial they cannot get")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "days free")).firstMatch.exists,
                       "The caption promises free days to a lapsed subscriber")
    }

    /// Never subscribed: Plus's trial, at the length Twofold.storekit gives it.
    @MainActor
    func testNeverSubscribedCoupleIsOfferedThePlusTrial() async throws {
        let scenario = try await Scenario.paired(tier: .none)
        let app = openPaywallFromHome(scenario)
        capture(app, "Paywall - never subscribed")
        require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Start my", "free trial")).firstMatch,
                timeout: 10, "A never-subscribed couple wasn't offered the Plus trial")
    }
}
