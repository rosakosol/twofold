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
//  screen. Requires a simulator that's already signed in, same as `AppWalkthroughUITests`.
//

import XCTest

final class NotificationDeepLinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(route: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-notificationRoute", route]
        app.launch()
        guard app.buttons["Home"].waitForExistence(timeout: 30) else {
            throw XCTSkip("No tab bar after 30s — this simulator isn't signed in.")
        }
        return app
    }

    /// A streak reminder has to land on the daily question, not wherever the app happened to be.
    /// The Games tab hosts it at the very top; before this fix the route was dropped during launch
    /// and the app opened on Home.
    @MainActor
    func testStreakReminderLandsOnTheDailyQuestion() throws {
        let app = try launch(route: "daily_question")

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
    func testDrawingNotificationOpensTheDrawingPad() throws {
        let app = try launch(route: "drawing_pad")

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

    /// Nothing to route on must leave the app exactly where it would otherwise have opened — a
    /// plain notification shouldn't yank anyone anywhere.
    @MainActor
    func testAnUnroutableNotificationChangesNothing() throws {
        let app = try launch(route: "something_we_dont_ship_yet")

        let home = app.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(home.isSelected, "An unrecognised route should leave the app on its default tab.")
    }
}
