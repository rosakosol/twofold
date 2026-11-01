//
//  NotificationDeepLinkUITests.swift
//  TwofoldUITests
//
//  The case that was actually broken: a notification tapped while the app isn't running delivers
//  the tap during launch, before any SwiftUI view exists to receive it. The route therefore has to
//  survive until the app has finished restoring its session — it can't just be broadcast and hoped
//  for.
//
//  These launch cold with a route already waiting (see `NotificationRouter`'s DEBUG seed, which
//  stands in for the tap) and assert the app ends up somewhere specific rather than on its default
//  screen. Each runs as a freshly paired Plus couple on the local stack.
//

import XCTest

final class NotificationDeepLinkUITests: E2ETestCase {

    @MainActor
    private func launch(route: String) async throws -> XCUIApplication {
        let app = launch(try await Scenario.pairedPlus(), arguments: ["-notificationRoute", route])
        waitForSignedInApp(app)
        return app
    }

    /// A streak reminder has to land on the daily question, not wherever the app happened to be.
    /// The Games tab hosts it at the very top; before this fix the route was dropped during launch
    /// and the app opened on Home.
    @MainActor
    func testStreakReminderLandsOnTheDailyQuestion() async throws {
        let app = try await launch(route: "daily_question")

        let games = app.buttons["Games"]
        XCTAssertTrue(games.waitForExistence(timeout: 10))
        // `isSelected` is what the tab bar exposes for the active tab.
        XCTAssertTrue(
            games.isSelected,
            "A daily_question notification should have switched to the Games tab, but the app opened on its default tab."
        )

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deeplink-daily-question"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The drawing pad is a full-screen destination rather than a tab, so success looks different:
    /// the tab bar is covered rather than re-selected.
    @MainActor
    func testDrawingNotificationOpensTheDrawingPad() async throws {
        let app = try await launch(route: "drawing_pad")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deeplink-drawing-pad"
        shot.lifetime = .keepAlways
        add(shot)

        // The pad presents over everything, so the Home tab button should no longer be hittable.
        let home = app.buttons["Home"]
        XCTAssertFalse(
            home.exists && home.isHittable,
            "A drawing_pad notification should have opened the pad over the tab bar."
        )
    }

    /// The other half of the same event. "<partner> saved a new drawing" is a notification about
    /// *their* pad, and used to open your own blank editor — it named a thing and then showed you
    /// something else. Distinguished by the title, which is the only thing separating the two
    /// screens once either is up.
    @MainActor
    func testPartnerDrawingNotificationOpensTheirPadNotYours() async throws {
        let app = try await launch(route: "partner_drawing_pad")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deeplink-partner-drawing-pad"
        shot.lifetime = .keepAlways
        add(shot)

        let home = app.buttons["Home"]
        XCTAssertFalse(
            home.exists && home.isHittable,
            "A partner_drawing_pad notification should have opened a pad over the tab bar."
        )
        // "<Name>'s pad", never "Your pad" — DrawingPadFullScreenView vs DrawingPadEditorView.
        XCTAssertFalse(
            app.staticTexts["Your pad"].exists,
            "A partner's drawing notification opened your own editor instead of their pad."
        )
        let theirPad = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "'s pad")).firstMatch
        XCTAssertTrue(
            theirPad.waitForExistence(timeout: 10),
            "Expected the partner's read-only pad, titled \"<Name>'s pad\"."
        )
    }

    /// Nothing to route on must leave the app exactly where it would otherwise have opened — a
    /// plain notification shouldn't yank anyone anywhere.
    @MainActor
    func testAnUnroutableNotificationChangesNothing() async throws {
        let app = try await launch(route: "something_we_dont_ship_yet")

        let home = app.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(home.isSelected, "An unrecognised route should leave the app on its default tab.")
    }

    /// CORE-6. Somebody without a subscription used to tap a flight or drawing push and get
    /// nothing at all: every route waited on a subscription that was never coming, for the rest of
    /// the session. A route that needs one now shows the paywall, which at least says why.
    @MainActor
    func testDrawingNotificationShowsThePaywallWithoutASubscription() async throws {
        let app = launch(try await Scenario.lapsed(), arguments: ["-notificationRoute", "partner_drawing_pad"])
        waitForSignedInApp(app)

        // Either state of the paywall: with plans, or — on a run with no StoreKit configuration,
        // like this one — the "couldn't load" state it shows without them.
        let paywall = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@", "Restore purchases", "Couldn't load subscription options"
        )).firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 20), "A lapsed couple's tap on a drawing push did nothing")
        capture(app, "Paywall from a notification")
    }
}
