//
//  WordSearchGameStore.swift
//  Twofold
//
//  One grid's worth of state: the letters, what has been found, and the clock.
//
//  The same arrangement `SudokuGameStore` documents at length — progress on the device while the
//  grid is in play, one `game_responses` row written when it is finished. Writing every find to the
//  server would trip `game_responses_advance_session` on the first word and complete the session on
//  the partner's first, leaving the grid unreachable for both with six words still hidden.
//

import Foundation
import Observation

@MainActor
@Observable
final class WordSearchGameStore: PuzzleScreenStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
        /// Abandoned by the partner, or archived by the cron, so it can no longer be finished —
        /// see `SudokuGameStore.Phase.ended`.
        case ended
    }

    let sessionID: UUID
    /// The result's way to the server and the partner. See `PuzzleResultLink`.
    let link: PuzzleResultLink
    /// A finished grid the server does not have yet.
    var resultPending: Bool { link.isPending }

    private(set) var phase: Phase = .loading
    private(set) var play: WordSearchPlayState?
    /// The run of cells under the player's finger right now. Empty when nobody is dragging.
    private(set) var selection: [Int] = []
    /// The word most recently found, for the screen to call out. Cleared by the next drag — it
    /// answers a question asked a moment ago.
    private(set) var lastFound: String?
    /// The partner's finished grid, once there is one.
    ///
    /// Non-nil always means a genuinely finished grid: RLS reveals a partner's response only once
    /// both sides have written one, and this game writes one only on completion.
    private(set) var partnerResult: WordSearchSummary?

    private var responderID: UUID? { link.responderID }
    private var clock: Task<Void, Never>?
    private let backend: any PuzzleSessionBackend

    var theme: WordSearchTheme? { play?.puzzle.theme }

    init(
        sessionID: UUID,
        backend: any PuzzleSessionBackend = LivePuzzleSessionBackend(),
        queue: any GameResponseQueue = DiskGameResponseQueue.shared
    ) {
        self.sessionID = sessionID
        self.backend = backend
        self.link = PuzzleResultLink(sessionID: sessionID, gameType: .wordSearch, backend: backend, queue: queue)
        link.refreshPartner = { [weak self] in await self?.refreshPartner() }
        link.partnerHasFinished = { [weak self] in self?.partnerResult != nil }
    }

    var canAbandon: Bool { phase == .ready && play?.isComplete == false }

    func abandonSession() async throws {
        try await abandon()
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await backend.fetchGameSession(id: sessionID)
            let me = backend.currentUserID
            link.begin(responderID: me)
            if detail.session.status.hasEnded {
                end()
                return
            }
            guard let round = detail.rounds.first else {
                phase = .failed("This grid has no round.")
                return
            }
            guard let theme = round.theme else {
                // Every word search round is written with a theme. A round without one this build
                // recognises is a row from a newer version, and generating a grid from a guessed
                // theme would hand the two partners different letters.
                phase = .failed("This grid is from a newer version of Twofold.")
                return
            }

            // The whole grid, from the round's id. Nothing was fetched to get here, which is what
            // makes a started grid playable with no connection.
            let puzzle = WordSearchGenerator.puzzle(for: round.contentID, theme: theme)

            let fromServer = detail.responses
                .first { $0.responderID == me }
                .flatMap { WordSearchPlayState.decoded(from: $0.answerValue, puzzle: puzzle) }
            let fromDevice = me
                .flatMap { PuzzleProgressCache.wordSearch.load(sessionID: sessionID, responderID: $0) }
                .flatMap { WordSearchPlayState.decoded(from: $0, puzzle: puzzle) }

            play = Self.furtherAlong(fromServer, fromDevice) ?? WordSearchPlayState(puzzle: puzzle)
            link.noteServerHasResult(fromServer?.isComplete == true)
            partnerResult = me.flatMap { Self.partnerResult(in: detail, me: $0) }
            phase = .ready

            // Finished here but never delivered. Sent again now, as well as on reconnect, on
            // foreground and by `GameResponseOutbox` — see `PuzzleResult`.
            if play?.isComplete == true, !link.hasSubmitted {
                submitResult()
            }
        } catch {
            phase = .failed(ErrorStateView.message(for: error))
        }
    }

    /// Which of the device's copy and the server's to carry on from.
    ///
    /// A grid only ever gains found words, so more found is strictly further on, and a finished
    /// grid beats an unfinished one however many words are on it. There is no merging the two: they
    /// are the same grid, and taking finds from both would build a board neither person played.
    private static func furtherAlong(
        _ first: WordSearchPlayState?,
        _ second: WordSearchPlayState?
    ) -> WordSearchPlayState? {
        switch (first, second) {
        case (nil, nil): return nil
        case let (value?, nil): return value
        case let (nil, value?): return value
        case let (a?, b?):
            if a.isComplete != b.isComplete { return a.isComplete ? a : b }
            return a.found.count >= b.found.count ? a : b
        }
    }

    // MARK: - Playing

    /// Starts a drag at one cell.
    func beginSelection(at index: Int) {
        guard play?.isComplete == false else { return }
        lastFound = nil
        selection = [index]
    }

    /// Extends the drag to another cell.
    ///
    /// A run that is not straight leaves the selection as it was rather than clearing it. A finger
    /// crossing a grid passes over a great many cells that were never meant, and a selection that
    /// vanished every time one of them was off-axis would be impossible to place.
    func extendSelection(to index: Int) {
        guard let start = selection.first, play?.isComplete == false else { return }
        guard let line = WordSearchPuzzle.line(from: start, to: index, size: WordSearchPuzzle.size) else { return }
        selection = line
    }

    /// Ends the drag, and records a word if that is what it was.
    func endSelection() {
        defer { selection = [] }
        guard var current = play, !current.isComplete, selection.count > 1 else { return }
        guard let placement = current.find(cells: selection) else { return }

        lastFound = placement.word
        play = current
        persistLocally()

        if current.isComplete {
            stopClock()
            submitResult()
        }
    }

    /// The one write to `game_responses` this game makes.
    private func submitResult() {
        guard let current = play, current.isComplete else { return }
        link.send(encoded: current.encoded, isCorrect: true, notifyDetail: notifyDetail)
    }

    /// Tries the result again if it is still waiting. The screen calls this on reconnecting and
    /// on returning to the foreground.
    func retryPendingResult() async {
        guard phase == .ready else { return }
        await link.retryPending(notifyDetail: notifyDetail)
    }

    /// Ends this grid for both partners, and drops the device's copy of it.
    func abandon() async throws {
        stopClock()
        try await BackendService.abandonGameSession(id: sessionID)
        // The device's own copy goes too, or the grid sits in the cache forever — harmless, but it
        // is the abandoned puzzle's last trace and nothing will ask for it again.
        if let me = responderID ?? backend.currentUserID {
            PuzzleProgressCache.wordSearch.remove(sessionID: sessionID, responderID: me)
        }
    }

    /// The session was ended elsewhere: the grid and any unsent result go, and the screen says so
    /// rather than offering a grid that can no longer be finished.
    private func end() {
        stopClock()
        phase = .ended
        if let me = responderID {
            PuzzleProgressCache.wordSearch.remove(sessionID: sessionID, responderID: me)
        }
        link.discard()
    }

    private var notifyDetail: String? { theme.map { "\($0.displayName) Word Search" } }

    private func persistLocally() {
        guard let play, let responderID else { return }
        PuzzleProgressCache.wordSearch.save(play.encoded, sessionID: sessionID, responderID: responderID)
    }

    // MARK: - The partner's side

    /// Re-reads only the partner's half. Deliberately leaves `play` alone: a refresh arriving
    /// mid-grid must not replace the finds under the player's hands with what the server last
    /// heard, which for a grid in progress is nothing at all.
    ///
    /// Also notices the session ending under it, and the server having this player's result.
    private func refreshPartner() async {
        guard let me = responderID else { return }
        guard let detail = try? await backend.fetchGameSession(id: sessionID) else { return }
        if detail.session.status.hasEnded {
            end()
            return
        }
        link.noteDelivered(in: detail)
        partnerResult = Self.partnerResult(in: detail, me: me)
    }

    private static func partnerResult(
        in detail: BackendService.GameSessionDetail,
        me: UUID
    ) -> WordSearchSummary? {
        guard let theirs = detail.responses.first(where: { $0.responderID != me }),
              let summary = WordSearchPlayState.summary(from: theirs.answerValue),
              // A row this build cannot read, or one that somehow is not a finished grid, is no
              // result at all — better the "waiting for them" card than a comparison against a
              // number we had to guess at.
              summary.complete
        else { return nil }
        return summary
    }

    // MARK: - The clock

    func startClock() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
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
