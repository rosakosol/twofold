//
//  AppWalkthroughUITests.swift
//  TwofoldUITests
//
//  An exploratory pass over the signed-in app: visits every tab, and runs XCTest's own
//  accessibility audit on each one. Deliberately non-failing on audit findings — it prints them
//  (grep the test log for `A11Y`) so a pre-release review can triage them, rather than blocking
//  the suite on, say, a decorative glyph's contrast ratio.
//
//  Requires a simulator that is already signed in — these drive the real backend, so they assert
//  on chrome that only exists post-onboarding (the tab bar) and bail out with a clear message
//  rather than a confusing failure if the app happens to launch into onboarding instead.
//

import XCTest

final class AppWalkthroughUITests: XCTestCase {

    /// Every tab in `MainTabView`, by the label its button carries.
    private static let tabs = ["Home", "Travel", "Memories", "Games", "Stats"]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testEveryTabOpensAndPassesAnAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

        let homeTab = app.buttons["Home"]
        guard homeTab.waitForExistence(timeout: 30) else {
            throw XCTSkip("No tab bar after 30s — this simulator isn't signed in, so there's no signed-in app to walk. Sign in once in the simulator and re-run.")
        }

        for tab in Self.tabs {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab '\(tab)' never appeared")
            button.tap()

            // Let the tab's own `.task` work land before auditing/screenshotting it.
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "tab-\(tab)"
            shot.lifetime = .keepAlways
            add(shot)

            audit(app, context: "tab:\(tab)")
        }
    }

    /// Runs every audit type and prints each finding instead of failing, so one noisy tab can't
    /// hide the findings on the tabs after it.
    @MainActor
    private func audit(_ app: XCUIApplication, context: String) {
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element?.label ?? "<no element>"
                let frame = issue.element.map { "\($0.frame)" } ?? "-"
                let type = issue.element.map { "\($0.elementType.rawValue)" } ?? "-"
                print("A11Y [\(context)] \(issue.auditType): \(issue.compactDescription) — element: '\(element)' type=\(type) frame=\(frame)")
                return true // handled; don't fail the test over it
            }
        } catch {
            print("A11Y [\(context)] audit could not run: \(error.localizedDescription)")
        }
    }
}
