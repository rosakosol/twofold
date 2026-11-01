//
//  OfflineWritesE2ETests.swift
//  TwofoldUITests
//
//  Work done while the backend can't take writes is kept and sent once it can (CORE-2, CORE-3,
//  HOME-1, HOME-2).
//
//  `TWOFOLD_E2E_WRITES_FAIL` makes every trip, memory and profile write fail as if offline while
//  reads keep working — the exact state the bugs lived in: the write failed, the next refresh
//  succeeded, and the refresh replaced the unsent work with the server's copy. `until-background`
//  lifts it when the app goes to the background, so coming back is the reconnect; `1` holds for
//  the whole launch, so the next launch is the one that sends.
//

import XCTest

final class OfflineWritesE2ETests: E2ETestCase {

    /// A sheet's field doesn't take focus from a tap made during its slide-in.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !app.keyboards.firstMatch.exists {
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        field.typeText(text)
    }

    /// A row in the Memories list, whose label combines the title with its place and date.
    private func memoryRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Home's appearance refreshes the memories — the refresh that used to drop unsent work.
    @MainActor
    private func visitHomeAndComeBack(_ app: XCUIApplication) {
        openTab("Home", in: app)
        sleep(3)
        openTab("Memories", in: app)
    }

    /// Polls the server, since the send happens in the background after the app comes back.
    @MainActor
    private func waitForServer(timeout: TimeInterval = 30, _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .seconds(1))
        }
        return false
    }

    @MainActor
    func testMemoryAddedWhileWritesFailIsKeptAndSentOnReturningToTheApp() async throws {
        let scenario = try await Scenario.pairedPlus()
        let app = launch(scenario, environment: ["TWOFOLD_E2E_WRITES_FAIL": "until-background"])
        waitForSignedInApp(app)

        openTab("Memories", in: app)
        require(app.buttons["Add memory"], "No Add memory button").tap()
        let title = require(app.textFields["Memory title"], timeout: 15, "Add memory form never opened")
        type("Written offline", into: title, in: app)
        // A place is required to save.
        app.buttons["Location"].tap()
        let search = require(app.searchFields["Type an address or place"], timeout: 10, "No location search")
        type("Rome", into: search, in: app)
        let rome = require(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Rome'")).firstMatch, timeout: 15, "Rome not offered")
        rome.tap()
        _ = search.waitForNonExistence(timeout: 20)
        sleep(1)
        require(app.buttons["Save"], "No Save button").tap()
        // A first memory queues the review prompt, which sits over the tab bar.
        dismissFirstLaunchSheets(app)

        require(memoryRow("Written offline", in: app), timeout: 15, "The memory never appeared in the list")
        visitHomeAndComeBack(app)
        require(memoryRow("Written offline", in: app), timeout: 10, "A refresh dropped the memory that hadn't been sent")
        capture(app, "Unsent memory still listed")
        let sentEarly = try await scenario.memoryRows().contains { $0.title == "Written offline" }
        XCTAssertFalse(sentEarly, "The write was supposed to fail; the harness flag did nothing")

        // Background and back: the writes come back, and returning to the foreground sends it.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let reached = try await waitForServer {
            try await scenario.memoryRows().contains { $0.title == "Written offline" }
        }
        XCTAssertTrue(reached, "The memory never reached the server after coming back to the app")

        visitHomeAndComeBack(app)
        require(memoryRow("Written offline", in: app), timeout: 10, "Gone from the list after it was sent")
        let copies = try await scenario.memoryRows().filter { $0.title == "Written offline" }.count
        XCTAssertEqual(copies, 1, "Sent more than once")
    }

    @MainActor
    func testMemoryEditMadeWhileWritesFailIsSentAtTheNextLaunch() async throws {
        let scenario = try await Scenario.pairedPlus()
        let memoryID = try await scenario.addMemory(title: "Where we met")
        var app = launch(scenario, environment: ["TWOFOLD_E2E_WRITES_FAIL": "1"])
        waitForSignedInApp(app)

        openTab("Memories", in: app)
        // The tab opens on the map, where the title is also a pin's caption; the list's row is
        // the one that opens the memory.
        require(app.buttons["List view"], timeout: 10, "No list/map toggle").tap()
        require(memoryRow("Where we met", in: app), timeout: 20, "The seeded memory isn't listed").tap()
        let field = require(app.textFields["Title"], timeout: 10, "No title field on the memory")
        field.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        // To the end of the title, then out with it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Where we met".count + 2))
        field.typeText("Where we really met\n")
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        visitHomeAndComeBack(app)
        require(memoryRow("Where we really met", in: app), timeout: 10, "A refresh put the old title back")
        capture(app, "Unsent edit still shown")
        let titleBefore = try await scenario.memoryRows().first { $0.id == memoryID }?.title
        XCTAssertEqual(titleBefore, "Where we met", "The write was supposed to fail; the harness flag did nothing")

        // Killed before it was sent, then opened again with the writes working.
        app.terminate()
        app = launch(scenario, keepDevice: true, signIn: false)
        waitForSignedInApp(app)
        let reached = try await waitForServer {
            try await scenario.memoryRows().first { $0.id == memoryID }?.title == "Where we really met"
        }
        XCTAssertTrue(reached, "The edit made before the app was killed never reached the server")
        openTab("Memories", in: app)
        require(memoryRow("Where we really met", in: app), timeout: 10, "The relaunched app doesn't show the edit")
    }
}
