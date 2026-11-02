//
//  FlightsAndTripsE2ETests.swift
//  TwofoldUITests
//
//  Flights and trips as a couple sees them, from seeded rows on the local stack (Batch 4, part A).
//
//    - A reunion next month with its flight attached is not "together now" (CORE-1 / FLT-1).
//    - Only past trips still leaves a way to plan the next one (FLT-28).
//    - An untracked flight that has flown says so, and isn't offered tracking (FLT-8, FLT-10).
//    - Ten minutes late reads as late on the departure card as well as the pill (FLT-13).
//    - The tracking screen's countdown moves while you watch it (FLT-11).
//
//  A flight screen is opened by its deep link, which is what a widget or Live Activity tap does,
//  rather than by finding it in the Travel panel.
//

import XCTest

final class FlightsAndTripsE2ETests: E2ETestCase {

    private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    @MainActor
    private func openFlight(_ id: UUID, in app: XCUIApplication) {
        app.open(URL(string: "twofold://flight/\(id.uuidString)")!)
    }

    /// Scrolls the screen until `element` is there, or gives up after a few swipes.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    /// Home shows the reunion card only when no flight is in its carousel, so the flight attached
    /// here is a cancelled one: out of the carousel, and — under the old rule, which counted any
    /// flight that hadn't landed — still enough to make the trip "Right now / Together" a month
    /// early. With a live flight the same bug drew the trip on the globe instead, which no
    /// accessibility query can see; the unit tests in TripLifecycleTests cover that case.
    @MainActor
    func testAReunionNextMonthWithItsFlightIsNotTogetherNow() async throws {
        let scenario = try await Scenario.pairedPlus()
        let tripID = try await scenario.addTrip(from: .melbourne, to: .rome, daysFromNow: 30)
        try await scenario.addFlight(departsIn: 30 * 86_400, arrivesIn: 30 * 86_400 + 15 * 3600, status: "cancelled", tripID: tripID)
        let app = launch(scenario)
        waitForSignedInApp(app)

        let next = text("Next reunion", in: app)
        XCTAssertTrue(scrollTo(next, in: app), "Home never showed the trip as the next reunion")
        XCTAssertFalse(text("Right now", in: app).exists, "A trip a month away read as happening right now")
        XCTAssertFalse(text("You're together now", in: app).exists, "A trip a month away said you're together now")
        capture(app, "Home - reunion next month")
    }

    @MainActor
    func testTravelWithOnlyPastTripsStillOffersToPlanOne() async throws {
        let scenario = try await Scenario.pairedPlus()
        try await scenario.addTrip(from: .melbourne, to: .rome, daysFromNow: -40)
        let app = launch(scenario)
        waitForSignedInApp(app)

        openTab("Travel", in: app)
        require(text("No upcoming trips", in: app), timeout: 30, "The Trips panel was blank with only past trips")
        capture(app, "Travel - only past trips")
    }

    @MainActor
    func testAFlownUntrackedFlightReadsAsFlownAndIsNotOfferedTracking() async throws {
        let scenario = try await Scenario.pairedPlus()
        // Ten days ago, saved without tracking, still marked scheduled.
        let flightID = try await scenario.addFlight(
            departsIn: -10 * 86_400, arrivesIn: -10 * 86_400 + 15 * 3600, tracking: false, refreshedNow: false
        )
        let app = launch(scenario)
        waitForSignedInApp(app)

        openFlight(flightID, in: app)
        let countdown = require(app.staticTexts["flight.countdown"], timeout: 30, "The flight screen never opened")
        XCTAssertTrue(countdown.label.hasPrefix("Flew"), "A flight that flew ten days ago reads '\(countdown.label)'")
        XCTAssertFalse(app.buttons["Turn on live tracking"].exists, "Offered to spend a tracking slot on a flight that has flown")
        XCTAssertTrue(text("No longer being tracked", in: app).exists, "The flown flight doesn't say tracking is over")
        capture(app, "Flight - flown, untracked")
    }

    @MainActor
    func testATenMinuteDelayReadsAsLateOnTheDepartureCard() async throws {
        let scenario = try await Scenario.pairedPlus()
        let flightID = try await scenario.addFlight(
            departsIn: 5 * 3600, arrivesIn: 20 * 3600, status: "delayed", departureDelaySeconds: 600
        )
        let app = launch(scenario)
        waitForSignedInApp(app)

        openFlight(flightID, in: app)
        require(text("Delayed 10 min", in: app), timeout: 30, "The pill doesn't say ten minutes late")
        XCTAssertTrue(scrollTo(text("+10 min", in: app), in: app), "The departure card doesn't say ten minutes late")
        XCTAssertFalse(app.staticTexts["On time"].exists, "The departure card said on time under a delayed pill")
        capture(app, "Flight - ten minutes late")
    }

    /// Waits over a minute, which is the point: the countdown is minute-resolution and used to be
    /// worked out once per render.
    @MainActor
    func testTheTrackingScreensCountdownMovesWhileOpen() async throws {
        let scenario = try await Scenario.pairedPlus()
        let flightID = try await scenario.addFlight(departsIn: 3 * 3600, arrivesIn: 18 * 3600)
        let app = launch(scenario)
        waitForSignedInApp(app)

        openFlight(flightID, in: app)
        let countdown = require(app.staticTexts["flight.countdown"], timeout: 30, "The flight screen never opened")
        let first = countdown.label
        XCTAssertTrue(first.hasPrefix("Departs in"), "got '\(first)'")

        let moved = NSPredicate(format: "label != %@", first)
        let result = XCTWaiter.wait(for: [expectation(for: moved, evaluatedWith: countdown)], timeout: 100)
        XCTAssertEqual(result, .completed, "The countdown sat at '\(first)' for over a minute and a half")
        capture(app, "Flight - countdown moved")
    }
}
