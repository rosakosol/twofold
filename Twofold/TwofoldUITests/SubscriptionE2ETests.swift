//
//  SubscriptionE2ETests.swift
//  TwofoldUITests
//
//  What a couple sees with and without a subscription, with the server and the device agreeing.
//
//  Two groups. `SubscriptionE2ETests` runs in the default test plan and needs nothing beyond the
//  local stack: RevenueCat is left unconfigured and the device's store answer comes from
//  `TWOFOLD_E2E_TIER`. `PaywallTrialCopyE2ETests` needs real products to put a price and a trial
//  on, so it runs only under the Purchases plan (Twofold-Purchases.xctestplan), which has the app
//  configure RevenueCat anonymously. That plan does reach RevenueCat's API for the offering, and
//  the App Store sandbox for the products — there is no local RevenueCat — but never as a test
//  account.
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

    /// Someone whose Premium has lapsed meets the Premium gate, and its way back to Premium,
    /// rather than screens the server will refuse.
    ///
    /// The RevenueCat webhook writes `subscription_active = false` on expiry and leaves the tier
    /// column as it was. The app used to unlock Premium on the tier alone, so with "premium" still
    /// in the column Hard and Expert stayed open: tapping one asked the server for a Premium puzzle
    /// and got a raw refusal instead of the paywall. Unpaired here, because that is the path that
    /// reads the column as it stands; a couple reaches the same stale tier through a foreground
    /// refresh or an offline launch (see `SubscriptionStateTests`).
    @MainActor
    func testLapsedPremiumMeetsThePremiumGate() async throws {
        let scenario = try await Scenario.solo(tier: .premium)
        try await LocalStack.send(
            "PATCH", "rest/v1/profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(scenario.me.id)")],
            body: ["subscription_active": false, "subscription_will_renew": false],
            as: .service
        )
        // Nothing on the device holds an entitlement any more either.
        let app = launch(scenario, environment: ["TWOFOLD_E2E_TIER": TestTier.lapsed.rawValue])
        waitForSignedInApp(app)

        openTab("Games", in: app)
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sudoku")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        require(tile, "No Sudoku tile on the Games hub").tap()
        let hard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hard")).firstMatch
        require(hard, "No Hard row on the difficulty picker").tap()

        // Either state of the paywall: with plans, or the "couldn't load" state it shows on a run
        // with no StoreKit configuration, like this one.
        let paywall = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@", "Restore purchases", "Couldn't load subscription options"
        )).firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 15), "A lapsed Premium subscriber's tap on Hard did not reach the paywall")
        capture(app, "Premium gate - lapsed")
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
/// What this proves, and what it does not. The products come from the App Store sandbox, not from
/// Twofold.storekit: a StoreKit configuration file, whether attached by the test plan or the
/// scheme, does not reach an app a UI test launches from `xcodebuild` (storekitd logs the requests
/// as "Sandbox" and sends them to amp-api.sandbox.apple.com), and the sandbox's Plus products carry
/// no introductory offer. So the test reads Plus's offer out of Twofold.storekit itself and hands
/// it to the app through `TWOFOLD_E2E_INTRO_OFFERS`, the way `TWOFOLD_E2E_TIER` already stands in
/// for Apple's eligibility answer. Both tests therefore get the same trial terms and differ only in
/// eligibility, which is the rule under test: the paywall's copy and its gate, on real offering
/// and price data. StoreKit's delivery of the offer is not tested here.
final class PaywallTrialCopyE2ETests: E2ETestCase {

    /// The introductory offer Twofold.storekit gives each subscription that has one, in the form
    /// `TWOFOLD_E2E_INTRO_OFFERS` takes. Read from the source tree, which the simulator can see, so
    /// the test follows the file rather than a copy of it.
    private func storeKitIntroOffers() throws -> (spec: String, periods: [String: String]) {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Twofold/Twofold.storekit")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let groups = json?["subscriptionGroups"] as? [[String: Any]] ?? []
        var entries: [String] = []
        var periods: [String: String] = [:]
        for subscription in groups.flatMap({ $0["subscriptions"] as? [[String: Any]] ?? [] }) {
            guard let id = subscription["productID"] as? String,
                  let offer = subscription["introductoryOffer"] as? [String: Any],
                  let mode = offer["paymentMode"] as? String,
                  let period = offer["subscriptionPeriod"] as? String
            else { continue }
            let count = offer["numberOfPeriods"] as? Int ?? 1
            entries.append("\(id)=\(mode):\(period):\(count)")
            if mode == "free" { periods[id] = period }
        }
        return (entries.joined(separator: ","), periods)
    }

    @MainActor
    private func openPaywallFromHome(_ scenario: Scenario) throws -> XCUIApplication {
        let offers = try storeKitIntroOffers()
        // The premise of both tests: Plus yearly, the plan the paywall opens on, has a two-week
        // free trial. If Twofold.storekit changes that, the expected copy below has to change too.
        XCTAssertEqual(offers.periods["com.orangefinch.Twofold.plus.yearly"], "P2W",
                       "Twofold.storekit no longer gives Plus yearly a two-week free trial")
        let app = launch(scenario, storeKit: true, environment: ["TWOFOLD_E2E_INTRO_OFFERS": offers.spec])
        waitForSignedInApp(app)
        require(app.buttons["See plans"], timeout: 20, "No 'See plans' on an unsubscribed couple's Home").tap()
        let failed = app.staticTexts["No subscription plans are available right now."]
        let subscribe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Subscribe", "Start my")).firstMatch
        require(subscribe, timeout: 30, failed.exists
            ? "The paywall loaded no plans — run the Purchases test plan, and check RevenueCat and the App Store sandbox are reachable"
            : "The paywall never showed its purchase button")
        return app
    }

    /// Lapsed: Apple will not give the Plus trial a second time, so the button must not offer it.
    @MainActor
    func testLapsedCoupleIsNotOfferedATrial() async throws {
        let scenario = try await Scenario.lapsed()
        let app = try openPaywallFromHome(scenario)
        capture(app, "Paywall - lapsed")
        // Either caption, trial or plain, so the paywall is known to have resolved its plans and
        // trials before the absence of trial copy is read as meaning anything.
        require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS[c] %@",
                                                     "Renews automatically", "days free")).firstMatch,
                timeout: 10, "The lapsed couple's paywall never showed its price caption")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "free trial")).firstMatch.exists,
                       "A lapsed subscriber was offered a free trial they cannot get")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "days free")).firstMatch.exists,
                       "The caption promises free days to a lapsed subscriber")
        XCTAssertTrue(app.buttons["Subscribe"].exists, "A lapsed subscriber's button should read plain 'Subscribe'")
    }

    /// Never subscribed: Plus's trial, at the length Twofold.storekit gives it, then the real price.
    @MainActor
    func testNeverSubscribedCoupleIsOfferedThePlusTrial() async throws {
        let scenario = try await Scenario.paired(tier: .none)
        let app = try openPaywallFromHome(scenario)
        capture(app, "Paywall - never subscribed")
        require(app.buttons["Start my 14-day free trial"], timeout: 10, "A never-subscribed couple wasn't offered the Plus trial")
        require(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "14 days free, then ")).firstMatch,
                timeout: 5, "The caption doesn't state the trial's length and the price after it")
    }
}
