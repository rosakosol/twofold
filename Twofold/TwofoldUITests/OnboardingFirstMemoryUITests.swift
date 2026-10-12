//
//  OnboardingFirstMemoryUITests.swift
//  TwofoldUITests
//
//  Reported: photos picked on onboarding's first-memory step do not end up on the memory.
//
//  Driven rather than unit-tested because the half of that path a unit test can reach —
//  `addMemory` and `PendingMemoryStore` — is already pinned by `OnboardingMemoryPhotoTests` and
//  sound. What is left is the picker, the photos sheet and the form, as onboarding presents them.
//
//  Reached with `-onboardingStep firstMemory` (DEBUG only, see `OnboardingModel.init`). The first
//  wait is long for the reason `LegalConsentUITests` gives.
//

import XCTest

final class OnboardingFirstMemoryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Both fields arrive in a sheet, and a tap during its slide-in doesn't take focus.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !app.keyboards.firstMatch.exists {
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        field.typeText(text)
    }

    /// Opens onboarding at the first memory, fills in a title and place, and opens the Photos
    /// sheet with the library ready to tap. Returns the library's photo cells.
    private func openPhotosSheet(_ app: XCUIApplication) -> XCUIElementQuery {
        app.launchArguments += ["-onboardingStep", "firstMemory"]
        app.launch()

        let title = app.textFields["Memory title"]
        XCTAssertTrue(title.waitForExistence(timeout: 300), "Never reached the first-memory form")
        type("Where we met", into: title, in: app)

        // A place first: the Photos button asks for one otherwise.
        app.buttons["Location"].tap()
        let search = app.searchFields["Type an address or place"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "No location search")
        type("Rome", into: search, in: app)
        let rome = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Rome'")).firstMatch
        XCTAssertTrue(rome.waitForExistence(timeout: 10), "Rome not offered")
        rome.tap()
        // Wait for the location sheet to finish closing: a sheet asked for mid-dismissal is dropped.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: search)
        wait(for: [gone], timeout: 10)
        sleep(1)

        for _ in 0..<3 where !app.navigationBars["Photos"].exists {
            app.buttons["Photos"].tap()
            _ = app.navigationBars["Photos"].waitForExistence(timeout: 4)
        }
        XCTAssertTrue(app.navigationBars["Photos"].exists, "Photos sheet did not open")

        // The library's photos carry this identifier; a bare `images.firstMatch` finds the
        // privacy header's icon above them instead.
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 15), "No photos in the inline picker")
        // Let the grid finish laying out: it reports cells while still showing "Loading…".
        sleep(2)
        // The picker's first-run "Private Access to Photos" card covers the grid and eats a tap.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 3) {
            ok.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
        }
        capture(app, "Photos sheet")
        return photos
    }

    /// The picker runs out of process, so its cells report as not hittable; tap the spot instead.
    private func tapPhoto(_ photo: XCUIElement) {
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testPickedPhotoReachesTheForm() throws {
        let app = XCUIApplication()
        let photos = openPhotosSheet(app)

        tapPhoto(photos.element(boundBy: 0))
        XCTAssertTrue(app.staticTexts["On this memory"].waitForExistence(timeout: 15), "Picked photo never reached the sheet's strip")
        capture(app, "Photo in the sheet")

        app.navigationBars["Photos"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 10), "Picked photo is not on the form after closing the sheet")
        capture(app, "Photo on the form")
    }

    /// Two photos tapped back to back, the second before the first has loaded. Each tap reports
    /// the whole selection so far, so a sheet that loads whatever it is handed adds the first
    /// photo twice.
    @MainActor
    func testTwoQuickPicksAddTwoPhotos() throws {
        let app = XCUIApplication()
        let photos = openPhotosSheet(app)

        tapPhoto(photos.element(boundBy: 0))
        tapPhoto(photos.element(boundBy: 1))
        XCTAssertTrue(app.staticTexts["On this memory"].waitForExistence(timeout: 15), "Picked photos never reached the sheet's strip")
        // Long enough for any second load to land too.
        sleep(3)
        capture(app, "Two photos in the sheet")

        app.navigationBars["Photos"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 10), "Picked photos are not on the form after closing the sheet")
        sleep(1)
        capture(app, "Two photos on the form")
        XCTAssertEqual(app.buttons.matching(identifier: "Remove photo").count, 2, "Expected exactly the two photos picked")
    }

    /// A tick means "added on this visit", so unticking takes the photo back off.
    @MainActor
    func testUntickingRemovesThePhoto() throws {
        let app = XCUIApplication()
        let photos = openPhotosSheet(app)

        tapPhoto(photos.element(boundBy: 0))
        XCTAssertTrue(app.staticTexts["On this memory"].waitForExistence(timeout: 15), "Picked photo never reached the sheet's strip")
        tapPhoto(photos.element(boundBy: 0))
        XCTAssertTrue(app.staticTexts["No photos yet"].waitForExistence(timeout: 10), "Unticking left the photo on the memory")
        capture(app, "Unticked")
    }
}
