//
//  WordGuessGameStore.swift
//  Twofold
//
//  One board's worth of state: the word, the guesses, and the clock.
//
//  Built on the same arrangement `SudokuGameStore` documents at length, and for the same reasons:
//  progress is kept on the device while a board is in play, and exactly one `game_responses` row is
//  written — when the board finishes. Writing every guess to the server would trip
//  `game_responses_advance_session` on the first one, mark the session `waiting_for_partner` on a
//  single letter typed, and complete it the moment the partner typed theirs. The board would then
//  be unreachable for both of them, with four guesses left.
//
//  Where this differs from sudoku: a board can finish *unsuccessfully*. Six wrong guesses is a
//  complete, submitted result — not an abandoned one — and everything downstream has to be able to
//  tell "missed it in six" from "got it in six".
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class WordGuessGameStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let sessionID: UUID

    private(set) var phase: Phase = .loading
    private(set) var play: WordGuessPlayState?
    /// What the player has typed but not yet submitted. Uppercased for the board; the word lists
    /// are lowercase and every comparison lowercases first.
    private(set) var draft: String = ""
    /// Why the last submission bounced, for the board to say so and then forget. Cleared by the
    /// next keystroke — it answers a question asked a moment ago.
    private(set) var rejection: WordGuessPlayState.Rejection?
    /// The partner's finished board, once there is one.
    ///
    /// Non-nil always means a genuinely finished board — won or lost. RLS reveals a partner's
    /// response only after both sides have written one, and this game writes one only when the
    /// board ends, so a row cannot appear here for a board still in play and cannot spoil anyone's
    /// guesses.
    private(set) var partnerResult: WordGuessSummary?

    private var responderID: UUID?
    private var clock: Task<Void, Never>?
    private var hasSubmitted = false
    private var channel: RealtimeChannelV2?

    var answer: String? { play?.answer }
    var canType: Bool { play?.canGuessAgain == true }

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await BackendService.fetchGameSession(id: sessionID)
            guard let round = detail.rounds.first else {
                phase = .failed("This board has no round.")
                return
            }
            guard let word = WordGuessWords.answer(for: round.contentID) else {
                // The bundled list did not load. Every board in the app would be unplayable, so
                // this is a broken build rather than a state worth recovering from — and inventing
                // a word here would hand the two partners different ones.
                phase = .failed("Word Guess couldn't load its dictionary.")
                return
            }

            let me = BackendService.currentUserID
            responderID = me

            let fromServer = detail.responses
                .first { $0.responderID == me }
                .flatMap { WordGuessPlayState.decoded(from: $0.answerValue, answer: word) }
            let fromDevice = me
                .flatMap { PuzzleProgressCache.wordGuess.load(sessionID: sessionID, responderID: $0) }
                .flatMap { WordGuessPlayState.decoded(from: $0, answer: word) }

            play = Self.furtherAlong(fromServer, fromDevice) ?? WordGuessPlayState(answer: word)
            hasSubmitted = fromServer?.isComplete == true
            partnerResult = me.flatMap { Self.partnerResult(in: detail, me: $0) }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Which of the device's copy and the server's to carry on from.
    ///
    /// Simpler than sudoku's equivalent, because a board only ever gains guesses: more guesses is
    /// strictly further on, and a finished board beats an unfinished one however many guesses are
    /// on it. There is no merging two boards — they are the same word, and picking guesses from
    /// both would build a board neither person ever played.
    private static func furtherAlong(
        _ first: WordGuessPlayState?,
        _ second: WordGuessPlayState?
    ) -> WordGuessPlayState? {
        switch (first, second) {
        case (nil, nil): return nil
        case let (value?, nil): return value
        case let (nil, value?): return value
        case let (a?, b?):
            if a.isComplete != b.isComplete { return a.isComplete ? a : b }
            return a.guesses.count >= b.guesses.count ? a : b
        }
    }

    // MARK: - Playing

    func type(_ letter: Character) {
        guard canType, draft.count < WordGuessWords.length else { return }
        rejection = nil
        draft.append(Character(letter.uppercased()))
    }

    func backspace() {
        guard canType, !draft.isEmpty else { return }
        rejection = nil
        draft.removeLast()
    }

    /// Commits the draft, if it is a word.
    ///
    /// A rejection leaves the draft on the board rather than clearing it. Being told "not a word"
    /// and having your five letters wiped means retyping four of them to change the fifth, which
    /// turns a small correction into a punishment.
    func submitGuess() {
        guard var current = play, current.canGuessAgain else { return }
        if let why = current.commit(draft) {
            rejection = why
            return
        }
        rejection = nil
        draft = ""
        play = current
        persistLocally()

        if current.isComplete {
            stopClock()
            submitResult()
        }
    }

    /// The one write to `game_responses` this game makes.
    ///
    /// Sent for a lost board as well as a won one. A miss is a result — it is what the partner is
    /// being compared against, and a board that quietly wrote nothing on failure would leave them
    /// waiting forever on someone who had in fact finished.
    private func submitResult() {
        guard !hasSubmitted, let current = play, current.isComplete else { return }
        hasSubmitted = true
        let encoded = current.encoded
        let id = sessionID
        Task {
            do {
                try await BackendService.submitGameResponse(
                    sessionID: id,
                    roundNumber: 1,
                    answerValue: encoded,
                    // Whether this player got the word — the column means "was this answer right",
                    // and for once in this app that has a literal answer.
                    isCorrect: current.isSolved
                )
                // If they finished first, their row was invisible until this insert: RLS reveals it
                // only once both sides have answered.
                await refreshPartner()
                await notifyPartnerOfResult()
            } catch {
                // The device's copy still holds the finished board, and `load()` prefers a complete
                // state, so reopening shows the result again rather than an empty board.
                hasSubmitted = false
            }
        }
    }

    /// Tells the other side the board is done — the same two events every other game sends.
    ///
    /// Which one depends on whether their result came back visible from the `refreshPartner()`
    /// above, since that can only happen once both responses are in.
    ///
    /// Sent for a solo player too, exactly as the other games do: `couple_id` is null,
    /// `notify-couple-event` finds no couple and returns without sending anything.
    private func notifyPartnerOfResult() async {
        await BackendService.notifyPartner(
            event: partnerResult == nil ? .gamePartnerFinished : .gameResultsReady,
            detail: GameType.wordGuess.displayName,
            sessionID: sessionID,
            gameType: .wordGuess
        )
    }

    private func persistLocally() {
        guard let play, let responderID else { return }
        PuzzleProgressCache.wordGuess.save(play.encoded, sessionID: sessionID, responderID: responderID)
    }

    // MARK: - The partner's side

    /// Subscribes to the session and re-reads the partner's result on every change, so a board that
    /// finishes while this screen is open becomes the comparison without it being reopened.
    ///
    /// Call from a `.task` of its own — this loops until cancelled. Pair with `stopRealtime()`.
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

    /// Re-reads only the partner's half.
    ///
    /// Deliberately leaves `play` alone: a refresh arriving mid-board must not replace the guesses
    /// under the player's hands with what the server last heard, which for a board in progress is
    /// nothing at all.
    private func refreshPartner() async {
        guard let me = responderID else { return }
        guard let detail = try? await BackendService.fetchGameSession(id: sessionID) else { return }
        partnerResult = Self.partnerResult(in: detail, me: me)
    }

    private static func partnerResult(
        in detail: BackendService.GameSessionDetail,
        me: UUID
    ) -> WordGuessSummary? {
        guard let theirs = detail.responses.first(where: { $0.responderID != me }),
              let summary = WordGuessPlayState.summary(from: theirs.answerValue)
        else { return nil }
        // A row this build cannot read is no result at all — better the "waiting for them" card
        // than a comparison against numbers we had to guess at.
        return summary
    }

    // MARK: - The clock

    /// Runs only while the board is on screen, so a game left open in a pocket does not report an
    /// afternoon's thinking. Time is recorded but never used to decide the comparison — see
    /// `WordGuessComparison.outcome` for why guesses, not speed, settle it.
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
