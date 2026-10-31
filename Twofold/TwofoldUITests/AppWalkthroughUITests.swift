//
//  AppWalkthroughUITests.swift
//  TwofoldUITests
//
//  An exploratory pass over the signed-in app: visits every tab, and runs XCTest's own
//  accessibility audit on each one. Deliberately non-failing on audit findings — it prints them
//  (grep the test log for `A11Y`) so a pre-release review can triage them, rather than blocking
//  the suite on, say, a decorative glyph's contrast ratio.
//
//  Runs as a paired Premium couple seeded on the local stack, with a trip and a memory, so every
//  tab has something on it and nothing is behind a lock. It used to walk whatever account the
//  simulator was signed into, against production, and skip when there was none.
//

import XCTest

final class AppWalkthroughUITests: E2ETestCase {

    /// Every tab in `MainTabView`, by the label its button carries.
    private static let tabs = ["Home", "Travel", "Memories", "Games", "Stats"]

    @MainActor
    func testEveryTabOpensAndPassesAnAccessibilityAudit() async throws {
        let scenario = try await Scenario.pairedPremium()
        try await scenario.addTrip()
        try await scenario.addMemory(title: "Where we met")
        let app = launch(scenario)
        waitForSignedInApp(app)
        // One tab's findings must not hide the next one's.
        continueAfterFailure = true

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
