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
        /// Abandoned by the partner, or archived by the cron, so it can no longer be finished —
        /// see `SudokuGameStore.Phase.ended`.
        case ended
    }

    let sessionID: UUID
    /// The board's result on its way to the server. See `PuzzleResult`.
    let result: PuzzleResult
    /// A finished board the server does not have yet.
    var resultPending: Bool { result.isPending }

    private(set) var phase: Phase = .loading
    private(set) var play: WordGuessPlayState?
    /// What the player has typed but not yet submitted. Uppercased for the board; the word lists
    /// are lowercase and every comparison lowercases first.
    private(set) var draft: String = ""
    /// Why the last submission bounced, for the board to say so and then forget. Cleared by the
    /// next keystroke — it answers a question asked a moment ago.
    private(set) var rejection: WordGuessPlayState.Rejection?
    /// Bumped on every refusal, including a repeat of the same one.
    ///
    /// `rejection` on its own cannot drive an animation: submitting the same non-word twice leaves
    /// it identical, so `onChange`/`sensoryFeedback` never fire the second time — which is exactly
    /// when somebody is most likely to be staring at the board wondering whether the button works.
    private(set) var rejectionNudge = 0
    /// The partner's finished board, once there is one.
    ///
    /// Non-nil always means a genuinely finished board — won or lost. RLS reveals a partner's
    /// response only after both sides have written one, and this game writes one only when the
    /// board ends, so a row cannot appear here for a board still in play and cannot spoil anyone's
    /// guesses.
    private(set) var partnerResult: WordGuessSummary?
    /// Their whole finished board, guesses and all, so the results can show how they got there and
    /// not just how many tries it took. Visible on exactly the same terms as `partnerResult`.
    private(set) var partnerPlay: WordGuessPlayState?
    /// When this word was played, for the share card: a game opened from the history is not today's.
    private(set) var playedAt: Date?

    private var responderID: UUID?
    private var clock: Task<Void, Never>?
    private var hasSubmitted = false
    private var submission: Task<Void, Never>?
    private var channel: RealtimeChannelV2?
    private let backend: any PuzzleSessionBackend

    var answer: String? { play?.answer }
    var canType: Bool { play?.canGuessAgain == true }

    init(
        sessionID: UUID,
        backend: any PuzzleSessionBackend = LivePuzzleSessionBackend(),
        queue: any GameResponseQueue = DiskGameResponseQueue.shared
    ) {
        self.sessionID = sessionID
        self.backend = backend
        self.result = PuzzleResult(sessionID: sessionID, gameType: .wordGuess, backend: backend, queue: queue)
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await backend.fetchGameSession(id: sessionID)
            let me = backend.currentUserID
            responderID = me
            if detail.session.status.hasEnded {
                end()
                return
            }
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

            let fromServer = detail.responses
                .first { $0.responderID == me }
                .flatMap { WordGuessPlayState.decoded(from: $0.answerValue, answer: word) }
            let fromDevice = me
                .flatMap { PuzzleProgressCache.wordGuess.load(sessionID: sessionID, responderID: $0) }
                .flatMap { WordGuessPlayState.decoded(from: $0, answer: word) }

            play = Self.furtherAlong(fromServer, fromDevice) ?? WordGuessPlayState(answer: word)
            hasSubmitted = fromServer?.isComplete == true
            if hasSubmitted, let me { result.noteDelivered(responderID: me) }
            partnerResult = me.flatMap { Self.partnerResult(in: detail, me: $0) }
            partnerPlay = me.flatMap { Self.partnerPlay(in: detail, me: $0, answer: word) }
            playedAt = detail.session.createdAt
            phase = .ready

            // Finished on this device but never heard of by the server: the send in
            // `submitGuess` failed (no signal, or the app was closed before it landed). Until it
            // lands the session stays open and the partner waits on a result that already exists.
            // Sent again now, as well as on reconnect, on foreground and by `GameResponseOutbox`.
            if play?.isComplete == true, !hasSubmitted {
                submitResult()
            }
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

        // Five letters is a guess. There was nothing else the row could do at this point — it is
        // full, so the only inputs left were ENTER and backspace — and asking for a second key to
        // confirm the word just typed is a step that existed because the keyboard had a button
        // spare, not because the game needed it.
        //
        // A word that is not in the list still costs nothing: `submitGuess` refuses it, leaves the
        // letters on the board and shakes the row, so backspacing to fix a typo works exactly as
        // it did. Only a *valid* word commits, which is the one case where pressing ENTER would
        // have been a formality.
        if draft.count == WordGuessWords.length {
            submitGuess()
        }
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
            rejectionNudge += 1
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
        guard !hasSubmitted, let current = play, current.isComplete, let me = responderID else { return }
        hasSubmitted = true
        submission = Task {
            let outcome = await result.send(
                encoded: current.encoded,
                // Whether this player got the word — the column means "was this answer right",
                // and for once in this app that has a literal answer.
                isCorrect: current.isSolved,
                notifyDetail: GameType.wordGuess.displayName,
                responderID: me
            )
            await handle(outcome)
        }
    }

    /// Tries the result again if it is still waiting. The screen calls this on reconnecting and
    /// on returning to the foreground.
    func retryPendingResult() async {
        guard phase == .ready, let me = responderID else { return }
        await submission?.value
        guard let outcome = await result.resendIfQueued(responderID: me) else {
            // Nothing left to send — it may have gone from `GameResponseOutbox` meanwhile.
            await refreshPartner()
            return
        }
        await handle(outcome)
    }

    private func handle(_ outcome: PuzzleResult.Outcome) async {
        switch outcome {
        case .sent:
            // If they finished first, their row was invisible until this insert: RLS reveals it
            // only once both sides have answered.
            await refreshPartner()
            await notifyPartnerOfResult()
        case .pending:
            break
        case .refused:
            // Almost always because the session was ended meanwhile; this read is what shows it.
            await refreshPartner()
        }
    }

    /// Ends this board for both partners — Word Guess had no way to, so a board neither of them
    /// was going to finish could only wait for the cron (GAME-4).
    func abandon() async throws {
        stopClock()
        try await BackendService.abandonGameSession(id: sessionID)
        if let me = responderID ?? backend.currentUserID {
            PuzzleProgressCache.wordGuess.remove(sessionID: sessionID, responderID: me)
        }
    }

    /// The session was ended elsewhere: the board and any unsent result go, and the screen says
    /// so rather than offering a board that can no longer be finished.
    private func end() {
        stopClock()
        phase = .ended
        if let me = responderID {
            PuzzleProgressCache.wordGuess.remove(sessionID: sessionID, responderID: me)
            result.discard(responderID: me)
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
        await backend.notifyPartner(
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
    ///
    /// Also notices the session ending under it, and the server having this player's result.
    private func refreshPartner() async {
        guard let me = responderID else { return }
        guard let detail = try? await backend.fetchGameSession(id: sessionID) else { return }
        if detail.session.status.hasEnded {
            end()
            return
        }
        if detail.responses.contains(where: { $0.responderID == me }) {
            result.noteDelivered(responderID: me)
        }
        partnerResult = Self.partnerResult(in: detail, me: me)
        if let word = answer {
            partnerPlay = Self.partnerPlay(in: detail, me: me, answer: word)
        }
    }

    private static func partnerPlay(
        in detail: BackendService.GameSessionDetail,
        me: UUID,
        answer: String
    ) -> WordGuessPlayState? {
        guard let theirs = detail.responses.first(where: { $0.responderID != me }) else { return nil }
        return WordGuessPlayState.decoded(from: theirs.answerValue, answer: answer)
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
