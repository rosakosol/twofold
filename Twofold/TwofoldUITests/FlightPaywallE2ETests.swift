//
//  FlightPaywallE2ETests.swift
//  TwofoldUITests
//
//  A couple the server says has no subscription, adding a flight: both flight search
//  (`resolve-flight`) and add flight (`add-flight`) refuse them with
//  `{"code":"subscription_required"}`, and the app answers with the paywall rather than the
//  server's own sentence.
//
//  The couple is free on the server and Plus on the device — what this device's store says, ahead
//  of a webhook that has not arrived, or a subscription that lapsed since the app last looked. That
//  is the only way to reach these refusals at all: a couple the app already knows is free meets
//  `SubscriptionRequiredView` at the sheet, before either function is called.
//
//  Needs the local stack's edge functions (`supabase functions serve`). Add flight starts from a
//  canned search result (`TWOFOLD_E2E_FLIGHT_SEARCH`), since the local stack has no AeroAPI key to
//  find a real one with; the `add-flight` behind it is the real one, and refuses before it would
//  call AeroAPI.
//

import XCTest

final class FlightPaywallE2ETests: E2ETestCase {

    /// The server's sentence. It must never be what the person reads.
    private static let serverSentence = "Tracking a new flight needs an active subscription"

    /// One result, a week out, for the add-flight test to choose.
    private static var cannedSearch: String {
        let iso = ISO8601DateFormatter()
        let out = Date().addingTimeInterval(7 * 86_400)
        let arrive = out.addingTimeInterval(24 * 3600)
        return """
        {"candidates":[{"faFlightId":"QFA1-e2e-\(UUID().uuidString)","identIata":"QF1","identIcao":"QFA1",\
        "operatorName":"Qantas","operatorIata":"QF","flightNumberIata":"QF1",\
        "origin":{"iata":"SYD","icao":"YSSY","city":"Sydney","timezone":"Australia/Sydney"},\
        "destination":{"iata":"LHR","icao":"EGLL","city":"London","timezone":"Europe/London"},\
        "scheduledOut":"\(iso.string(from: out))","scheduledIn":"\(iso.string(from: arrive))",\
        "status":"Scheduled","isTrackable":true}]}
        """
    }

    @MainActor
    private func launchFreeCoupleWithPlusOnTheDevice(environment: [String: String] = [:]) async throws -> XCUIApplication {
        let scenario = try await Scenario.paired(tier: .none)
        // The entry step recognises "QF1" from the airlines table, which the local stack starts
        // without. Reference data rather than anybody's, so it is written as it is in production.
        try await LocalStack.send(
            "POST", "rest/v1/airlines",
            body: ["iata": "QF", "icao": "QFA", "name": "Qantas"],
            as: .service,
            prefer: "resolution=merge-duplicates"
        )
        var environment = environment
        environment["TWOFOLD_E2E_TIER"] = TestTier.plus.rawValue
        let app = launch(scenario, environment: environment)
        waitForSignedInApp(app)
        return app
    }

    /// Travel, the Flights section, "+", then QF1 for today — as far as the search.
    @MainActor
    private func searchForQF1(in app: XCUIApplication) {
        openTab("Travel", in: app)
        require(app.buttons["Flights"], timeout: 15, "The Travel panel has no Flights section").tap()
        require(app.buttons["Add a flight"], timeout: 10, "The Flights section has no add button").tap()

        let field = require(app.textFields["Flight number or airport"], timeout: 15, "The add-flight sheet never opened")
        field.tap()
        field.typeText("QF1")
        let detected = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Detected flight number")).firstMatch
        require(detected, timeout: 15, "QF1 was not recognised as a Qantas flight number").tap()

        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today")).firstMatch
        require(today, timeout: 10, "The date step has no Today row").tap()
    }

    @MainActor
    private func paywall(in app: XCUIApplication) -> XCUIElement {
        // Either state of the paywall: with plans, or the "couldn't load" state it shows on a run
        // with no StoreKit configuration, like this one.
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@", "Restore purchases", "Couldn't load subscription options"
        )).firstMatch
    }

    @MainActor
    private func serverSentence(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", Self.serverSentence)).firstMatch
    }

    @MainActor
    func testAFreeCouplesFlightSearchOpensThePaywall() async throws {
        let app = try await launchFreeCoupleWithPlusOnTheDevice()
        searchForQF1(in: app)

        let paywall = paywall(in: app)
        XCTAssertTrue(paywall.waitForExistence(timeout: 30), "A refused flight search did not open the paywall")
        XCTAssertFalse(serverSentence(in: app).exists, "The server's refusal sentence reached the screen")
        capture(app, "Flight search - paywall")
    }

    @MainActor
    func testAFreeCouplesAddFlightOpensThePaywall() async throws {
        let app = try await launchFreeCoupleWithPlusOnTheDevice(environment: ["TWOFOLD_E2E_FLIGHT_SEARCH": Self.cannedSearch])
        searchForQF1(in: app)

        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QF1")).firstMatch
        require(result, timeout: 20, "The canned search result never showed").tap()
        require(app.buttons["Add flight"], timeout: 15, "The confirm step never opened").tap()

        let paywall = paywall(in: app)
        XCTAssertTrue(paywall.waitForExistence(timeout: 30), "A refused add did not open the paywall")
        XCTAssertFalse(serverSentence(in: app).exists, "The server's refusal sentence reached the screen")
        capture(app, "Add flight - paywall")

        // Closed without buying: back on the confirm step, as it was, with nothing in red.
        require(app.buttons["Close"], timeout: 5, "The paywall has no close button").tap()
        XCTAssertTrue(app.buttons["Add flight"].waitForExistence(timeout: 10), "Closing the paywall did not return to the confirm step")
        XCTAssertFalse(serverSentence(in: app).exists, "The confirm step showed the server's sentence after the paywall closed")
        capture(app, "Add flight - paywall closed")
    }
}
