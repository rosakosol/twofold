//
//  PuzzleResult.swift
//  Twofold
//
//  Getting a generated puzzle's one result to the server, however long that takes (GAME-3).
//
//  Sudoku, Word Guess and Word Search each write a single `game_responses` row, when the puzzle is
//  finished. That send used to be tried once, and again only if that same puzzle was reopened: a
//  screen left open while the connection came back, an app brought back to the foreground, or a
//  player who simply never reopened it all left the partner waiting on a result that existed only
//  on one phone — while the screen said "Your time is saved".
//
//  Now the result goes into `PendingGameResponseStore` before it is sent and leaves once the
//  server has it or refuses it. The open screen retries on reconnect and on foreground, and
//  `GameResponseOutbox` sends whatever is left at launch, on foreground and on reconnect with no
//  game screen open at all — the same moments `AppModel.syncPendingWrites()` replays its outbox.
//
//  The queue is the one the deck games already use rather than `PendingWriteStore`. A result is a
//  game answer like any other — same table, same upsert, same reason to be cleared on sign-out —
//  and the deck queue's per-session reads and its remapping of answers given in a session started
//  offline (`LocalGameSessionSync`) are things `PendingWriteStore` has no notion of.
//

import Foundation

/// The backend calls a puzzle screen makes, behind a protocol so a test can play a puzzle against
/// a session that is offline, has been ended, or refuses the result.
protocol PuzzleSessionBackend {
    var currentUserID: UUID? { get }
    func fetchGameSession(id: UUID) async throws -> BackendService.GameSessionDetail
    func submitGameResponse(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool?) async throws
    func notifyPartner(event: BackendService.CoupleNotificationEvent, detail: String?, sessionID: UUID, gameType: GameType) async
    /// The Remind button's push. Whether it went.
    func sendGameReminder(detail: String, sessionID: UUID, gameType: GameType) async -> Bool
}

struct LivePuzzleSessionBackend: PuzzleSessionBackend {
    var currentUserID: UUID? { BackendService.currentUserID }

    func fetchGameSession(id: UUID) async throws -> BackendService.GameSessionDetail {
        try await BackendService.fetchGameSession(id: id)
    }

    func submitGameResponse(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool?) async throws {
        // The end-to-end tests' stand-in for a connection that drops writes, as in
        // `LiveCoupleDataBackend` (`TWOFOLD_E2E_WRITES_FAIL`, DEBUG only).
        if E2ELaunch.writesFail { throw URLError(.notConnectedToInternet) }
        try await BackendService.submitGameResponse(
            sessionID: sessionID, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect
        )
    }

    func notifyPartner(event: BackendService.CoupleNotificationEvent, detail: String?, sessionID: UUID, gameType: GameType) async {
        await BackendService.notifyPartner(event: event, detail: detail, sessionID: sessionID, gameType: gameType)
    }

    func sendGameReminder(detail: String, sessionID: UUID, gameType: GameType) async -> Bool {
        await BackendService.sendGameReminder(detail: detail, sessionID: sessionID, gameType: gameType)
    }
}

/// Where queued answers are kept. `PendingGameResponseStore` in the app; a test hands in one held
/// in memory, so it neither reads nor clears the file other suites use.
protocol GameResponseQueue: AnyObject {
    func all() -> [PendingGameResponse]
    func put(_ response: PendingGameResponse)
    func remove(id: UUID)
}

final class DiskGameResponseQueue: GameResponseQueue {
    static let shared = DiskGameResponseQueue()

    func all() -> [PendingGameResponse] { PendingGameResponseStore.all() }
    func put(_ response: PendingGameResponse) { PendingGameResponseStore.put(response) }
    func remove(id: UUID) { PendingGameResponseStore.remove(id: id) }
}

extension GameSessionStatus {
    /// Abandoned by either partner or archived by the cron. The server refuses any answer to a
    /// session in either state (20261116000000), so a puzzle in one can no longer be finished.
    var hasEnded: Bool { self == .abandoned || self == .archived }
}

/// One puzzle's result on its way to the server.
@Observable
final class PuzzleResult {
    enum Outcome: Equatable {
        /// The server has it.
        case sent
        /// Not sent yet. Kept, and sent at the next chance.
        case pending
        /// The server said no, and always will — almost always because the session was ended
        /// meanwhile. Dropped from the queue.
        case refused
    }

    let sessionID: UUID
    let gameType: GameType
    /// True while a finished result is waiting to be sent, which is what the screen shows rather
    /// than telling somebody their time is saved when only their phone has it.
    private(set) var isPending = false

    @ObservationIgnored private let backend: any PuzzleSessionBackend
    @ObservationIgnored private let queue: any GameResponseQueue

    init(sessionID: UUID, gameType: GameType, backend: any PuzzleSessionBackend, queue: any GameResponseQueue) {
        self.sessionID = sessionID
        self.gameType = gameType
        self.backend = backend
        self.queue = queue
    }

    /// Queues the result, then sends it.
    func send(encoded: String, isCorrect: Bool?, notifyDetail: String?, responderID: UUID) async -> Outcome {
        let item = PendingGameResponse(
            sessionID: sessionID,
            roundNumber: 1,
            responderID: responderID,
            answerValue: encoded,
            isCorrect: isCorrect,
            resultGameType: gameType,
            resultNotifyDetail: notifyDetail
        )
        queue.put(item)
        return await deliver(item)
    }

    /// Sends the result still queued for this puzzle, if there is one. Nil when nothing is queued:
    /// it was never finished here, or it has been sent — perhaps by `GameResponseOutbox`, while
    /// this screen was in the background.
    func resendIfQueued(responderID: UUID) async -> Outcome? {
        guard let item = queued(responderID: responderID) else {
            isPending = false
            return nil
        }
        return await deliver(item)
    }

    /// The server has this player's result, however it got there.
    func noteDelivered(responderID: UUID) {
        if let item = queued(responderID: responderID), !GameResponseOutbox.isSending(item.id) {
            queue.remove(id: item.id)
        }
        isPending = false
    }

    /// Takes a queued result out unsent, because the session it is for has ended.
    func discard(responderID: UUID) {
        if let item = queued(responderID: responderID) { queue.remove(id: item.id) }
        isPending = false
    }

    private func queued(responderID: UUID) -> PendingGameResponse? {
        queue.all().last { $0.sessionID == sessionID && $0.responderID == responderID && $0.roundNumber == 1 }
    }

    private func deliver(_ item: PendingGameResponse) async -> Outcome {
        // The outbox is sending this very item. A second send would be harmless — it is an upsert
        // — but would mean a second push to the partner; this screen catches up through realtime
        // or the next retry instead.
        guard GameResponseOutbox.claim(item.id) else {
            isPending = true
            return .pending
        }
        defer { GameResponseOutbox.release(item.id) }
        do {
            try await backend.submitGameResponse(
                sessionID: item.sessionID,
                roundNumber: item.roundNumber,
                answerValue: item.answerValue,
                isCorrect: item.isCorrect
            )
            queue.remove(id: item.id)
            isPending = false
            return .sent
        } catch where BackendService.isPermanentRefusal(error) {
            queue.remove(id: item.id)
            isPending = false
            return .refused
        } catch {
            isPending = true
            return .pending
        }
    }
}

/// Sends the game answers left in `PendingGameResponseStore` with no game screen open.
///
/// Called with `AppModel.syncPendingWrites()`, so at launch, on returning to the foreground and on
/// reconnecting. Before this a deck answer queued offline was sent only from that deck's own
/// screen, and a puzzle's result only from that puzzle's — so a partner could wait indefinitely on
/// an answer sitting on the other phone.
///
/// Leaves alone answers for a session started offline: those wait for `LocalGameSessionSync` to
/// make the session real, since until then their session id exists only on this device.
enum GameResponseOutbox {
    /// Answers being sent right now, by this drain or by a puzzle screen, so the two never send
    /// the same one at once and the partner gets one push rather than two.
    private static var sending: Set<UUID> = []
    /// Which account's flush is running, by `generation`; nil when none is.
    private static var flushingGeneration: Int?
    /// Moves on at every sign-out (`reset()`), so a flush started before one can tell it is now
    /// working for an account that has gone.
    private static var generation = 0

    static func claim(_ id: UUID) -> Bool { sending.insert(id).inserted }
    static func release(_ id: UUID) { sending.remove(id) }
    static func isSending(_ id: UUID) -> Bool { sending.contains(id) }

    /// Called at sign-out. A flush still waiting on the server stops when it hears back, without
    /// touching the queue or pushing the partner, and no longer counts as running — the "already
    /// flushing" flag used to outlive the account, so the next one's answers were not sent until
    /// the old request finished, however long that took.
    static func reset() {
        generation += 1
        sending = []
        flushingGeneration = nil
    }

    /// Oldest first. Stops at the first failure that is not a refusal: the connection is down,
    /// and the rest would fail the same way one timeout at a time. A refused answer is for a
    /// session that has ended, or that this account can no longer write to, and leaves the queue.
    static func flush(
        backend: any PuzzleSessionBackend = LivePuzzleSessionBackend(),
        queue: any GameResponseQueue = DiskGameResponseQueue.shared,
        isLocalSession: (UUID) -> Bool = { LocalGameSessionStore.session(id: $0) != nil }
    ) async {
        let started = generation
        guard flushingGeneration != started, let me = backend.currentUserID else { return }
        flushingGeneration = started
        defer { if flushingGeneration == started { flushingGeneration = nil } }

        let waiting = queue.all()
            .filter { $0.responderID == me && !isLocalSession($0.sessionID) }
            .sorted { $0.queuedAt < $1.queuedAt }
        for item in waiting {
            // Re-read, so an answer replaced or sent meanwhile is not sent again.
            guard generation == started else { return }
            guard queue.all().contains(where: { $0.id == item.id }), claim(item.id) else { continue }
            defer { release(item.id) }
            do {
                try await backend.submitGameResponse(
                    sessionID: item.sessionID,
                    roundNumber: item.roundNumber,
                    answerValue: item.answerValue,
                    isCorrect: item.isCorrect
                )
                // Signed out while it was in the air: the queue is the next account's now.
                guard generation == started else { return }
                queue.remove(id: item.id)
                if let gameType = item.resultGameType {
                    await notifyOfResult(item, gameType: gameType, me: me, backend: backend)
                }
            } catch where BackendService.isPermanentRefusal(error) {
                guard generation == started else { return }
                queue.remove(id: item.id)
            } catch {
                break
            }
        }
    }

    /// The push the puzzle screen sends after its own successful send: "your partner finished" if
    /// theirs is still to come, "results are ready" if it is already in. Their result is visible
    /// only once both are in (RLS), so seeing it is what decides.
    private static func notifyOfResult(_ item: PendingGameResponse, gameType: GameType, me: UUID, backend: any PuzzleSessionBackend) async {
        let detail = try? await backend.fetchGameSession(id: item.sessionID)
        let bothIn = detail?.responses.contains { $0.responderID != me } ?? false
        await backend.notifyPartner(
            event: bothIn ? .gameResultsReady : .gamePartnerFinished,
            detail: item.resultNotifyDetail,
            sessionID: item.sessionID,
            gameType: gameType
        )
    }
}
