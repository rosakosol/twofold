//
//  SudokuGameStore.swift
//  Twofold
//
//  One puzzle's worth of state: the grid, what the player has written in it, and the clock.
//
//  ---------------------------------------------------------------------------
//  Why progress is saved on the device and not to `game_responses`
//  ---------------------------------------------------------------------------
//
//  The obvious design is to autosave the grid into `game_responses` on every tap, which would give
//  free cross-device resume. It cannot work, and the reason is worth stating because the absence
//  looks like an oversight:
//
//  `game_responses_advance_session` fires AFTER INSERT and counts distinct responders on the round.
//  A sudoku session has one round, so the first autosave would put the session in
//  `waiting_for_partner`, and the partner's first autosave — their first tap, not their solve —
//  would satisfy "both answered, last round" and mark the whole thing `completed`, with a
//  `completed_at`. `start_sudoku_session` only resumes `active` and `waiting_for_partner` sessions,
//  so the next time either of them opened Sudoku they would be handed a brand new puzzle and the
//  half-finished one would be unreachable. That is precisely the stranding the resume logic exists
//  to prevent.
//
//  For every other game a response row means "this player answered". Keeping that true means
//  writing the row once, when the puzzle is solved — so in-progress state lives in
//  `SudokuProgressCache` and the server learns about the puzzle when there is something to compare.
//
//  The cost is honest: a puzzle abandoned mid-solve and resumed on a *different* device starts over.
//  A reinstall loses it too. Same-device resume, which is what actually happens, is intact.
//

import Foundation
import Observation

@MainActor
@Observable
final class SudokuGameStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let sessionID: UUID

    private(set) var phase: Phase = .loading
    private(set) var generated: SudokuPuzzle?
    private(set) var play: SudokuPlayState?
    /// Cells to light up as duplicated. Recomputed on every change rather than tracked
    /// incrementally — 81 cells against a 20-peer table is nothing, and an incrementally
    /// maintained highlight is a thing that goes subtly stale.
    private(set) var conflicts: Set<Int> = []
    private(set) var justSolved = false

    var selected: Int?
    var isNotesMode = false

    private var undoStack: [SudokuPlayState] = []
    private var responderID: UUID?
    private var clock: Task<Void, Never>?
    private var hasSubmitted = false

    var difficulty: SudokuDifficulty? { generated?.difficulty }
    var canUndo: Bool { !undoStack.isEmpty }

    /// How many of each digit are still to be placed, for greying out a finished number on the pad.
    /// Nine of a digit means every one of them is on the board.
    func remaining(of value: UInt8) -> Int {
        guard let play else { return 9 }
        return 9 - (0..<81).count { play[$0] == value }
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await BackendService.fetchGameSession(id: sessionID)
            guard let round = detail.rounds.first else {
                phase = .failed("This puzzle has no round.")
                return
            }
            guard let difficulty = round.difficulty else {
                // Every sudoku round is written with one. A round without it is a row this build
                // does not understand, and generating a puzzle at a guessed difficulty would hand
                // the two partners different grids.
                phase = .failed("This puzzle is from a newer version of Twofold.")
                return
            }

            // The whole puzzle, from the round's id. No content was fetched to get here — this is
            // what makes a started puzzle playable with no connection.
            let generated = SudokuGenerator.puzzle(for: round.contentID, difficulty: difficulty)
            self.generated = generated

            let me = BackendService.currentUserID
            responderID = me

            let fromServer = detail.responses
                .first { $0.responderID == me }
                .flatMap { SudokuPlayState.decoded(from: $0.answerValue, puzzle: generated.puzzle) }
            let fromDevice = me.flatMap {
                SudokuProgressCache.load(sessionID: sessionID, responderID: $0, puzzle: generated.puzzle)
            }

            let restored = SudokuPlayState.furtherAlong(fromServer, fromDevice)
            play = restored ?? SudokuPlayState(puzzle: generated.puzzle)
            hasSubmitted = fromServer?.isComplete == true
            recomputeConflicts()
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Playing

    func select(_ index: Int) {
        guard (0..<81).contains(index) else { return }
        selected = (selected == index) ? nil : index
    }

    func enter(_ value: UInt8) {
        guard let index = selected, let generated, var play, !play.isComplete else { return }
        guard !generated.isGiven(index) else { return }

        undoStack.append(play)
        if isNotesMode {
            play.toggleNote(value, at: index, puzzle: generated.puzzle)
        } else {
            // Tapping the digit already in the cell takes it out again, which is how every other
            // sudoku behaves and saves reaching for erase.
            if play[index] == value {
                play.erase(at: index, puzzle: generated.puzzle)
            } else {
                play.place(value, at: index, puzzle: generated.puzzle)
            }
        }
        apply(play)
    }

    func erase() {
        guard let index = selected, let generated, var play, !play.isComplete else { return }
        guard !generated.isGiven(index) else { return }
        undoStack.append(play)
        play.erase(at: index, puzzle: generated.puzzle)
        apply(play)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        play = previous
        recomputeConflicts()
        persistLocally()
    }

    private func apply(_ updated: SudokuPlayState) {
        play = updated
        recomputeConflicts()
        checkForSolve()
        persistLocally()
    }

    private func recomputeConflicts() {
        conflicts = play?.conflicts() ?? []
    }

    // MARK: - Finishing

    private func checkForSolve() {
        guard let generated, var play, !play.isComplete else { return }
        guard play.isSolved(solution: generated.solution) else { return }

        play.markComplete()
        self.play = play
        stopClock()
        justSolved = true
        selected = nil
        submitSolve()
    }

    /// The one write to `game_responses` this game makes. See the note at the top of the file.
    private func submitSolve() {
        guard !hasSubmitted, let play, play.isComplete else { return }
        hasSubmitted = true
        let encoded = play.encoded
        let id = sessionID
        Task {
            do {
                try await BackendService.submitGameResponse(
                    sessionID: id, roundNumber: 1, answerValue: encoded, isCorrect: true
                )
            } catch {
                // The local copy still holds the finished grid, and `load()` prefers a complete
                // state over an incomplete one, so reopening the puzzle offers the solve again
                // rather than the board.
                hasSubmitted = false
            }
        }
    }

    private func persistLocally() {
        guard let play, let responderID else { return }
        SudokuProgressCache.save(play, sessionID: sessionID, responderID: responderID)
    }

    // MARK: - The clock

    /// Runs only while the board is on screen. A puzzle left open overnight has not been played
    /// overnight, and the comparison screen shows these numbers side by side.
    func startClock() {
        guard clock == nil, play?.isComplete == false else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard var current = self.play, !current.isComplete else { return }
                current.elapsed += 1
                self.play = current
            }
        }
    }

    func stopClock() {
        clock?.cancel()
        clock = nil
        persistLocally()
    }
}
