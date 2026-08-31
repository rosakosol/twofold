//
//  PullToRefreshUITests.swift
//  TwofoldUITests
//
//  Pins that the main tabs actually carry a pull-to-refresh, which they didn't — every screen
//  refreshed only on appear and on foreground, so a screen showing stale data had no manual way
//  to be told to go and look again.
//
//  Asserts on the refresh control itself rather than on any data changing: what's being tested is
//  that the gesture is wired up on each screen, and a refresh against production may legitimately
//  return exactly what's already displayed. The control only exists while a refresh is running, so
//  finding it *is* the assertion that the pull started one.
//
//  Read-only against production — pulling to refresh writes nothing.
//

import XCTest

final class PullToRefreshUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        // Orientation has bitten measurements in this suite before — a simulator left in landscape
        // by an earlier run carries over into the next one.
        XCUIDevice.shared.orientation = .portrait
        guard app.buttons["Home"].waitForExistence(timeout: 30) else {
            throw XCTSkip("Not signed in on this simulator.")
        }
        return app
    }

    /// Drags the screen down past the refresh threshold and reports whether it started a refresh.
    ///
    /// Reads a counter rather than looking for the spinner. XCUITest quiesces the app before every
    /// accessibility query, so a refresh that finishes in under a second is always already over by
    /// the time anything can observe its control — every screen looked like it had no refresh at
    /// all, including ones that plainly did. `refreshAllCount` (DEBUG-only, see `AppModel`) is
    /// still there afterwards.
    @MainActor
    private func pullDownStartsRefresh(in app: XCUIApplication) -> String? {
        let probe = app.descendants(matching: .any)["refreshAllCount"]
        guard probe.waitForExistence(timeout: 10) else { return "the refreshAllCount probe isn't in the tree" }
        let before = Int(probe.value as? String ?? "") ?? -1

        // A SwiftUI `List` surfaces as a collection view on current iOS, not as a table or a
        // scroll view — Memories is built on one, and querying only the first two reported it as
        // having nothing to pull on at all.
        let candidates = [app.scrollViews.firstMatch, app.collectionViews.firstMatch, app.tables.firstMatch]
        guard let surface = candidates.first(where: { $0.waitForExistence(timeout: 5) }) else {
            return "no scrollable surface to pull on"
        }
        // Each attempt starts somewhere different, because no single point is safe on every tab.
        // The scroll view's frame spans the whole window, so dy 0.1 lands on the navigation bar and
        // the press never reaches the content; mid-screen on Home is the relationship globe, which
        // is a map and swallows pans wholesale; elsewhere a press that begins on a card's own
        // Button sometimes wins the gesture instead of the scroll. The left margin (dx 0.08) is
        // page background on every tab, which is why it's in the list. None of these are bugs in
        // the thing being tested, so the drag is retried rather than pinned to one lucky
        // coordinate.
        for (startX, startY) in [(0.08, 0.35), (0.5, 0.28), (0.08, 0.55), (0.5, 0.45)] {
            let top = surface.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: startY))
            let bottom = surface.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.95))
            top.press(forDuration: 0.2, thenDragTo: bottom, withVelocity: .slow, thenHoldForDuration: 0.5)

            // The refresh runs against production, so give the count a moment to move rather than
            // reading it the instant the finger lifts.
            let moved = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    (Int(app.descendants(matching: .any)["refreshAllCount"].value as? String ?? "") ?? before) > before
                },
                object: nil
            )
            if XCTWaiter().wait(for: [moved], timeout: 12) == .completed { return nil }
        }
        return "refreshAllCount stayed at \(before) after four pulls from different points"
    }

    @MainActor
    private func assertPullToRefresh(onTab tab: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let app = try launch()
        if tab != "Home" {
            let button = app.buttons[tab]
            guard button.waitForExistence(timeout: 10) else {
                throw XCTSkip("No \(tab) tab on this build.")
            }
            button.tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
        }
        if tab == "Memories" {
            // Memories opens on the map, which has no pull-to-refresh and shouldn't: dragging a map
            // pans it. The list is the half of that tab a pull belongs on.
            let listMode = app.buttons["list.bullet"]
            guard listMode.waitForExistence(timeout: 10) else { throw XCTSkip("No list/map toggle on Memories.") }
            listMode.tap()
        }
        if let failure = pullDownStartsRefresh(in: app) {
            XCTFail("Pulling down on \(tab) started no refresh — \(failure)", file: file, line: line)
        }
    }

    @MainActor func testHomePullsToRefresh() throws { try assertPullToRefresh(onTab: "Home") }

    @MainActor func testGamesPullsToRefresh() throws { try assertPullToRefresh(onTab: "Games") }
    @MainActor func testStatsPullsToRefresh() throws { try assertPullToRefresh(onTab: "Stats") }
    @MainActor func testMemoriesPullsToRefresh() throws { try assertPullToRefresh(onTab: "Memories") }

    // Memories is tested in list mode only — see `assertPullToRefresh`. Travel is deliberately
    // absent altogether. Its list lives inside a drag-to-expand panel
    // (DraggablePanelHost), where a downward drag already means "collapse this panel" — adding a
    // refresh to the same gesture would make one drag do two things. Its data (trips and flights)
    // still refreshes from every other tab's pull, since they all call `AppModel.refreshAll()`.
}
