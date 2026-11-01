//
//  ConcurrentEditsE2ETests.swift
//  TwofoldUITests
//
//  Both partners editing the same memory or trip (HOME-5, HOME-7).
//
//  The partner's edit reaches the server while this phone still shows the older copy, and then
//  this phone edits a different field. An edit used to send every field from that older copy, so
//  the partner's change was silently undone; now only the field changed here is sent.
//

import XCTest

final class ConcurrentEditsE2ETests: E2ETestCase {

    private func row(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Polls the server, since a send can land a moment after the screen moves on.
    @MainActor
    private func waitForServer(timeout: TimeInterval = 20, _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .seconds(1))
        }
        return false
    }

    @MainActor
    func testRenamingAMemoryKeepsTheNoteThePartnerJustWrote() async throws {
        let scenario = try await Scenario.pairedPlus()
        let memoryID = try await scenario.addMemory(title: "Where we met")
        let app = launch(scenario)
        waitForSignedInApp(app)

        openTab("Memories", in: app)
        require(app.buttons["List view"], timeout: 10, "No list/map toggle").tap()
        require(row("Where we met", in: app), timeout: 20, "The seeded memory isn't listed").tap()
        let field = require(app.textFields["Title"], timeout: 10, "No title field on the memory")

        // The partner writes a note from their phone while this one has the memory open.
        try await scenario.updateAsPartner("memories", id: memoryID, ["note": "The café by the station"])

        field.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Where we met".count + 2))
        field.typeText("Where we really met\n")

        let renamed = try await waitForServer {
            try await scenario.row("memories", id: memoryID, columns: "title")?["title"] as? String == "Where we really met"
        }
        XCTAssertTrue(renamed, "The rename never reached the server")
        let note = try await scenario.row("memories", id: memoryID, columns: "note")?["note"] as? String
        XCTAssertEqual(note, "The café by the station", "Renaming the memory wiped the note the partner had just written")
        capture(app, "Renamed memory")
    }

    @MainActor
    func testChangingATripsCategoryKeepsTheNotesThePartnerJustWrote() async throws {
        let scenario = try await Scenario.pairedPlus()
        let tripID = try await scenario.addTrip(from: .melbourne, to: .rome, daysFromNow: 30, category: "together")
        let app = launch(scenario)
        waitForSignedInApp(app)

        openTab("Travel", in: app)
        require(row("Rome", in: app), timeout: 20, "The seeded trip isn't on the Travel tab").tap()
        require(app.buttons["More options"], timeout: 10, "No menu on the trip").tap()
        require(app.buttons["Edit trip"], timeout: 5, "No Edit trip in the menu").tap()
        require(app.navigationBars["Edit trip"], timeout: 10, "The trip editor never opened")

        try await scenario.updateAsPartner("trips", id: tripID, ["notes": "Ferry at six"])

        require(app.buttons["Reunion"], timeout: 5, "No Reunion category").tap()
        require(app.buttons["Save"], "No Save button").tap()

        let recategorised = try await waitForServer {
            try await scenario.row("trips", id: tripID, columns: "category")?["category"] as? String == "seeing_each_other"
        }
        XCTAssertTrue(recategorised, "The category change never reached the server")
        let notes = try await scenario.row("trips", id: tripID, columns: "notes")?["notes"] as? String
        XCTAssertEqual(notes, "Ferry at six", "Changing the category wiped the notes the partner had just written")
        capture(app, "Recategorised trip")
    }
}
