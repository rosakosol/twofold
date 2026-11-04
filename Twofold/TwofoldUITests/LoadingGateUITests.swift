//
//  LoadingGateUITests.swift
//  TwofoldUITests
//
//  The memory detail screen and the Memories map hold themselves back until their pieces have
//  loaded, so they appear once rather than piece by piece. What must never happen is the other
//  failure — a screen that waits for ever on a photo or a map that isn't coming.
//
//  Runs in `-demoMode` (no backend), with `-demoLatency` set far beyond either screen's wait: the
//  photos take a minute to arrive. Both screens must be usable long before that.
//

import XCTest

final class LoadingGateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchDemo(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-demoMode", "-demoLatency", "60"] + arguments
        app.launch()
        return app
    }

    /// The photo is a minute away; the screen's wait is a couple of seconds. The panel shows with the
    /// photo's placeholder well before the photo could have.
    @MainActor
    func testMemoryDetailShowsWithoutWaitingForASlowPhoto() {
        let app = launchDemo(["-demoScreen", "memory"])
        // Launch on this machine can itself take several seconds, hence the margin — still far
        // short of the photo's sixty.
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 25), "The memory panel waited on its photo")
    }

    /// The pins' photos are a minute away too. The cover must lift on its own timeout, after which
    /// a pin can be tapped — under the cover it can't, since the cover takes the touches.
    @MainActor
    func testMemoriesMapUncoversWithoutWaitingForPinPhotos() {
        let app = launchDemo(["-demoTab", "memories"])
        let pin = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'memor'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 25), "No memory pin on the map")
        let hittable = NSPredicate(format: "isHittable == true")
        let uncovered = expectation(for: hittable, evaluatedWith: pin)
        wait(for: [uncovered], timeout: 15)
    }
}
