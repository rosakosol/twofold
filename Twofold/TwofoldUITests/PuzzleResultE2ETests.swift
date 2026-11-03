//
//  PuzzleResultE2ETests.swift
//  TwofoldUITests
//
//  A puzzle's result, and a puzzle that ended, end to end (GAME-3, 2-games-NEW-2, GAME-4).
//
//  `TWOFOLD_E2E_WRITES_FAIL` takes the result's send down as if offline while reads keep working,
//  which is the state GAME-3 lived in: the solve was on the phone, the screen said it was saved,
//  and nothing sent it again unless that same puzzle was reopened.
//
//  Sudoku is solved through the Hint button, as in `SudokuE2ETests`.
//

import XCTest

final class PuzzleResultE2ETests: E2ETestCase {

    @MainActor
    private func openEasySudoku(_ app: XCUIApplication) {
        openTab("Games", in: app)
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sudoku")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        require(tile, "No Sudoku tile on the Games hub").tap()
        let easy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Easy")).firstMatch
        require(easy, "No Easy row on the difficulty picker").tap()
    }

    @MainActor
    private func emptyCell(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", ", empty")).firstMatch
    }

    @MainActor
    private func solveWithHints(_ app: XCUIApplication) {
        let empty = emptyCell(app)
        require(empty, timeout: 20, "The puzzle never loaded")
        let hint = app.buttons["Hint"]
        var filled = 0
        while empty.exists, filled < 81 {
            empty.tap()
            hint.tap()
            filled += 1
        }
        XCTAssertFalse(empty.exists, "Still empty cells after \(filled) hints")
    }

    /// Polls the server, since the send happens in the background.
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
    func testSolveThatCouldNotBeSentSaysSoAndIsSentOnReturningToTheApp() async throws {
        let scenario = try await Scenario.solo()
        let app = launch(scenario, environment: ["TWOFOLD_E2E_WRITES_FAIL": "until-background"])
        waitForSignedInApp(app)

        openEasySudoku(app)
        solveWithHints(app)

        require(app.descendants(matching: .any)["game.pendingBanner"], timeout: 15, "Solved with the send failing, but nothing says the result is waiting")
        XCTAssertFalse(
            app.staticTexts["Your time is saved."].exists,
            "The screen says the time is saved while only the phone has it"
        )
        capture(app, "Result waiting")
        let sessions = try await scenario.sudokuSessions()
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.status, "active", "The result reached the server while writes were down")

        // Coming back to the app is the reconnect.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        let sent = try await waitForServer { try await scenario.gameSessionStatus(session.id) == "completed" }
        XCTAssertTrue(sent, "The waiting result was never sent after returning to the app")
        let banner = app.descendants(matching: .any)["game.pendingBanner"]
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: banner)], timeout: 15), .completed,
                       "The result was sent, but the screen still says it is waiting")
        capture(app, "Result sent")
    }

    @MainActor
    func testSolveLeftUnsentIsSentAtTheNextLaunchWithNoPuzzleOpen() async throws {
        let scenario = try await Scenario.solo()
        let first = launch(scenario, environment: ["TWOFOLD_E2E_WRITES_FAIL": "1"])
        waitForSignedInApp(first)

        openEasySudoku(first)
        solveWithHints(first)
        require(first.descendants(matching: .any)["game.pendingBanner"], timeout: 15, "Solved with the send failing, but nothing says the result is waiting")
        let sessions = try await scenario.sudokuSessions()
        let session = try XCTUnwrap(sessions.first)
        first.terminate()
        let statusAfterFirstLaunch = try await scenario.gameSessionStatus(session.id)
        XCTAssertEqual(statusAfterFirstLaunch, "active")

        // The same device and session, writes working, and the puzzle never reopened.
        let second = launch(scenario, keepDevice: true, signIn: false)
        waitForSignedInApp(second)

        let sent = try await waitForServer { try await scenario.gameSessionStatus(session.id) == "completed" }
        XCTAssertTrue(sent, "A solve left unsent was not sent at the next launch — only reopening that puzzle used to send it")
    }

    @MainActor
    func testPuzzleThePartnerAbandonedShowsAsEndedRatherThanABoard() async throws {
        let scenario = try await Scenario.pairedPlus()
        let sessionID = try await scenario.startSudoku()
        let app = launch(scenario)
        waitForSignedInApp(app)

        // The hub lists the open grid under Open Games, whose card begins "Sudoku" as the game's
        // tile does — so the first match may open the board itself rather than the picker. Either
        // way it is the grid above: Easy resumes the couple's open Easy grid.
        openTab("Games", in: app)
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sudoku")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        require(tile, "No Sudoku on the Games hub").tap()
        let easy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Easy")).firstMatch
        if easy.waitForExistence(timeout: 5) { easy.tap() }
        require(emptyCell(app), timeout: 20, "The puzzle never loaded")

        try await scenario.abandonAsPartner(sessionID)
        let abandoned = try await scenario.gameSessionStatus(sessionID)
        XCTAssertEqual(abandoned, "abandoned")

        // Realtime is not part of the local stack the tests run, so returning to the app is what
        // makes the screen read the session again.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        require(app.descendants(matching: .any)["game.ended"], timeout: 20, "A puzzle the partner abandoned is still offered as a board")
        XCTAssertFalse(emptyCell(app).exists, "The board is still there under the ended state")
        capture(app, "Ended by partner")
    }

    @MainActor
    func testWordGuessCanBeAbandonedFromItsMenu() async throws {
        let scenario = try await Scenario.pairedPlus()
        let app = launch(scenario)
        waitForSignedInApp(app)

        openTab("Games", in: app)
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Word Guess")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        require(tile, "No Word Guess tile on the Games hub").tap()
        require(app.buttons["Play today's word"], "No Play button on the Word Guess screen").tap()

        require(app.buttons["More options"], timeout: 20, "Word Guess has no menu to abandon a board from").tap()
        require(app.buttons["Abandon this word"], "No Abandon item in the menu").tap()
        require(app.buttons["Abandon"], "No confirmation for abandoning").tap()

        require(app.buttons["Play today's word"], timeout: 15, "Abandoning did not go back to the Word Guess screen")
        let wordGuesses = try await scenario.sessions(gameType: "word_guess")
        let session = try XCTUnwrap(wordGuesses.first)
        XCTAssertEqual(session.status, "abandoned")
        capture(app, "Word Guess abandoned")
    }
}
