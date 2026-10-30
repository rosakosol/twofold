//
//  SudokuRematchTests.swift
//  TwofoldTests
//
//  "Play another" on a solved solo puzzle used to abandon it first, on the belief that a solo
//  session never reaches `completed`. It does: `advance_game_session`'s solo branch completes the
//  session on the one response a sudoku takes. `abandon_game_session` has no status guard, so the
//  solve was turned into an abandonment, and the puzzle vanished from Previous games and from the
//  Completed history. Nothing about a rematch needs the old session ended —
//  `start_sudoku_session` resumes only `active` and `waiting_for_partner`.
//
//  Driven through `SudokuGameStore` with a recording `SudokuSessionActions`, because the property
//  that matters is a call that must never be made.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
private final class RecordingSessionActions: SudokuSessionActions {
    var started: [SudokuDifficulty] = []
    var abandoned: [UUID] = []
    let nextSessionID = UUID()
    var startError: Error?

    func start(difficulty: SudokuDifficulty) async throws -> BackendService.SudokuSessionStart {
        started.append(difficulty)
        if let startError { throw startError }
        return BackendService.SudokuSessionStart(
            sessionID: nextSessionID, puzzleID: UUID(), difficulty: difficulty, resumed: false
        )
    }

    func abandon(sessionID: UUID) async throws {
        abandoned.append(sessionID)
    }
}

private struct Offline: Error {}

@MainActor
struct SudokuRematchTests {

    @Test("a solo player's next puzzle never abandons the one just solved")
    func soloRematchKeepsTheSolve() async throws {
        let solvedID = UUID()
        let store = SudokuGameStore(sessionID: solvedID)
        let actions = RecordingSessionActions()

        let started = try await store.startAnother(difficulty: .easy, using: actions)

        #expect(actions.abandoned.isEmpty)
        #expect(actions.started == [.easy])
        #expect(started.sessionID == actions.nextSessionID)
    }

    @Test("a failed start leaves the solved puzzle alone too")
    func failedStartAbandonsNothing() async {
        let store = SudokuGameStore(sessionID: UUID())
        let actions = RecordingSessionActions()
        actions.startError = Offline()

        await #expect(throws: Offline.self) {
            try await store.startAnother(difficulty: .hard, using: actions)
        }
        #expect(actions.abandoned.isEmpty)
    }

    /// The other half of the same seam, so the recorder above is known to see an abandon when one
    /// is made — otherwise "nothing was abandoned" could just mean nothing was watching.
    @Test("abandoning from the menu does end this session")
    func abandonEndsThisSession() async throws {
        let id = UUID()
        let store = SudokuGameStore(sessionID: id)
        let actions = RecordingSessionActions()

        try await store.abandon(using: actions)

        #expect(actions.abandoned == [id])
        #expect(actions.started.isEmpty)
    }
}
