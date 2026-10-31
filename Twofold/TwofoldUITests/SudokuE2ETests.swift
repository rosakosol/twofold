//
//  SudokuE2ETests.swift
//  TwofoldUITests
//
//  A solo Sudoku, solved and followed by "Play another" — the GAME-1 path.
//
//  "Play another" used to abandon the puzzle on screen before starting the next one. A solo
//  session completes on its single response, and `abandon_game_session` has no status guard, so
//  the abandon turned a finished solve into an abandonment: it vanished from Previous games and
//  from the server's history alike. `SudokuRematchTests` pins the store's ordering; this pins what
//  a person sees, and what the database ends up holding.
//
//  Solved through the Hint button, one empty cell at a time. Hints only ever write the solution's
//  digit, so this needs no solver and cannot get the grid wrong, and the result counts as a solve
//  like any other — which is all GAME-1 is about.
//

import XCTest

final class SudokuE2ETests: E2ETestCase {

    @MainActor
    func testSolvedSoloPuzzleSurvivesPlayAnotherAndShowsInHistory() async throws {
        let scenario = try await Scenario.solo()
        let app = launch(scenario)
        waitForSignedInApp(app)

        openTab("Games", in: app)
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sudoku")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        require(tile, "No Sudoku tile on the Games hub").tap()

        let easy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Easy")).firstMatch
        require(easy, "No Easy row on the difficulty picker").tap()

        let empty = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", ", empty")).firstMatch
        require(empty, timeout: 20, "The puzzle never loaded")
        let hint = app.buttons["Hint"]

        // Bounded by the size of the grid, so a hint that stopped filling cells fails here rather
        // than looping forever.
        var filled = 0
        while empty.exists, filled < 81 {
            empty.tap()
            hint.tap()
            filled += 1
        }
        XCTAssertFalse(empty.exists, "Still empty cells after \(filled) hints")

        let playAnother = app.buttons["Play another easy puzzle"]
        require(playAnother, timeout: 15, "Solved, but no 'Play another' on the finished puzzle")
        capture(app, "Solved")

        let solved = try await scenario.sudokuSessions()
        XCTAssertEqual(solved.count, 1)
        let solvedID = try XCTUnwrap(solved.first?.id)
        playAnother.tap()

        // The next grid is up when it has blanks again.
        require(empty, timeout: 20, "'Play another' never produced a new puzzle")
        let sessions = try await scenario.sudokuSessions()
        XCTAssertEqual(sessions.count, 2, "Play another should have started exactly one new session")
        let status = try await scenario.gameSessionStatus(solvedID)
        XCTAssertEqual(status, "completed", "The solved puzzle was turned into '\(status ?? "nil")' by Play another — GAME-1")

        app.buttons["Back"].tap()
        let solvedRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label MATCHES %@", "Easy Sudoku", ".*You: [0-9]+:[0-9]{2}.*")
        ).firstMatch
        for _ in 0..<4 where !solvedRow.exists { app.swipeUp() }
        require(solvedRow, timeout: 15, "The solved puzzle isn't in Previous games with its time")
        capture(app, "Previous games")
    }
}
