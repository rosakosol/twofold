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
import Supabase

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
    /// Cells a "check" turned up as wrong, cleared by the next edit. Not persisted: it is the
    /// answer to a question asked a moment ago, not part of the puzzle's state.
    private(set) var mistakes: Set<Int> = []
    private(set) var justSolved = false
    /// The partner's finished time, once there is one.
    ///
    /// Non-nil always means a genuine completed solve. RLS only reveals a partner's response after
    /// both sides have written one, and this game writes a response only on solve (see the note at
    /// the top of this file) — so a row cannot appear here for a puzzle they are still working on,
    /// and this can never leak a half-finished grid or spoil a solve in progress.
    private(set) var partnerResult: SudokuSolveSummary?

    var selected: Int?
    var isNotesMode = false

    private var undoStack: [SudokuPlayState] = []
    private var responderID: UUID?
    private var clock: Task<Void, Never>?
    private var hasSubmitted = false
    private var channel: RealtimeChannelV2?

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
            partnerResult = me.flatMap {
                Self.partnerResult(in: detail, me: $0, puzzle: generated.puzzle)
            }
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
        mistakes = []
        persistLocally()
    }

    // MARK: - Asking for help

    /// Fills in one cell, preferring whichever is selected and otherwise choosing the first empty
    /// one. Counted against the solve — see `SudokuPlayState.hintsUsed`.
    ///
    /// A hint lands on the selected cell even when that cell already holds a wrong digit: someone
    /// who selects a cell and asks for help is asking about *that* cell, and refusing because they
    /// had already guessed would be the least helpful moment to be strict.
    func useHint() {
        guard let generated, var play, !play.isComplete else { return }

        let target = selected.flatMap { index -> Int? in
            generated.isGiven(index) ? nil : index
        } ?? (0..<81).first { !generated.isGiven($0) && play[$0] != generated.solution[$0] }

        guard let target else { return }
        undoStack.append(play)
        play.revealCell(at: target, solution: generated.solution, puzzle: generated.puzzle)
        selected = target
        mistakes = []
        apply(play)
    }

    /// Marks every entry that disagrees with the solution, and counts the look.
    ///
    /// The marks are transient — the next edit clears them — rather than sticky. A permanent
    /// "this is wrong" badge turns one check into a running correctness display, which is a
    /// different and much larger favour than the player asked for, and one the other partner's
    /// solve would not have had.
    func checkMistakes() {
        guard let generated, var play, !play.isComplete else { return }
        undoStack.append(play)
        play.recordCheck()
        self.play = play
        mistakes = play.mistakes(solution: generated.solution)
        persistLocally()
    }

    private func apply(_ updated: SudokuPlayState) {
        play = updated
        recomputeConflicts()
        mistakes = []
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
                // If they finished first, their response was invisible until this insert — RLS only
                // reveals it once both sides have answered. Realtime would echo this same insert
                // back and trigger the read anyway, but that leaves the comparison depending on a
                // live socket to show a result both halves of which are already on the server.
                await refreshPartner()
                await notifyPartnerOfSolve()
            } catch {
                // The local copy still holds the finished grid, and `load()` prefers a complete
                // state over an incomplete one, so reopening the puzzle offers the solve again
                // rather than the board.
                hasSubmitted = false
            }
        }
    }

    /// Tells the other side that a grid was just finished — the same two pushes the other four
    /// games send from `GameSessionStore.performSubmit`, which this game does not go through.
    ///
    /// Without them a sudoku was a game you could only discover had been played by opening it. The
    /// pitch is "solve it apart, compare when you're done", and both halves of that were left to
    /// chance: the partner was never told a grid was waiting, and whoever solved first — having
    /// seen "waiting for them" and put the phone down — was never told the comparison had arrived.
    /// The Nudge button covered only the first, and only if the person who finished remembered.
    ///
    /// Which of the two goes out is decided by the `refreshPartner()` that ran just above. Their
    /// result being visible at all means both responses are in, since RLS reveals a partner's row
    /// only once both sides have written one.
    ///
    /// Sent unconditionally for a solo player too, exactly as the other games do: `couple_id` is
    /// null, `notify-couple-event` finds no couple and returns without sending anything.
    private func notifyPartnerOfSolve() async {
        // The difficulty is the whole of what names a sudoku — there is no deck title — and it
        // lands inside the push copy, so a nil reads better as an omission than as an empty string.
        let detail = difficulty.map { "\($0.displayName) Sudoku" }
        await BackendService.notifyPartner(
            event: partnerResult == nil ? .gamePartnerFinished : .gameResultsReady,
            detail: detail,
            sessionID: sessionID,
            gameType: .sudoku
        )
    }

    private func persistLocally() {
        guard let play, let responderID else { return }
        SudokuProgressCache.save(play, sessionID: sessionID, responderID: responderID)
    }

    // MARK: - The partner's side

    /// Subscribes to the session and re-reads the partner's result on every change, so a solve that
    /// lands while this screen is open becomes the comparison without needing the screen reopened.
    ///
    /// Call from a `.task` of its own — this loops until cancelled, so sharing `load()`'s task would
    /// mean the board never rendered. Pair with `stopRealtime()`.
    func subscribeRealtime() async {
        let (channel, stream) = BackendService.subscribeToGameSession(id: sessionID)
        self.channel = channel
        for await _ in stream {
            await refreshPartner()
        }
    }

    func stopRealtime() {
        guard let channel else { return }
        Task { await BackendService.unsubscribe(channel) }
        self.channel = nil
    }

    /// Re-reads only the partner's half of the session.
    ///
    /// Deliberately leaves `play` alone. A refresh arriving mid-solve must not be able to replace
    /// the grid under the player's hands with whatever the server last heard — which, for a puzzle
    /// in progress, is nothing at all, since the one response row is written on solve.
    private func refreshPartner() async {
        guard let generated, let me = responderID else { return }
        guard let detail = try? await BackendService.fetchGameSession(id: sessionID) else { return }
        partnerResult = Self.partnerResult(in: detail, me: me, puzzle: generated.puzzle)
    }

    private static func partnerResult(
        in detail: BackendService.GameSessionDetail,
        me: UUID,
        puzzle: SudokuGrid
    ) -> SudokuSolveSummary? {
        guard let theirs = detail.responses.first(where: { $0.responderID != me }),
              let state = SudokuPlayState.decoded(from: theirs.answerValue, puzzle: puzzle),
              // A response this build cannot read, or one that somehow isn't a finished grid, is no
              // time at all — better the "waiting for them" card than a comparison against a number
              // we had to guess at.
              state.isComplete
        else { return nil }
        return SudokuSolveSummary(
            elapsed: state.elapsed,
            hintsUsed: state.hintsUsed,
            checksUsed: state.checksUsed
        )
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
