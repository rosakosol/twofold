//
//  PuzzleResultTests.swift
//  TwofoldTests
//
//  A puzzle's one result reaching the server (GAME-3), and a puzzle that was ended elsewhere
//  showing as ended rather than as a board (2-games-NEW-2).
//
//  The result used to be sent once and again only when that same puzzle was reopened, while the
//  screen said "Your time is saved". And none of the puzzle screens read the session's status, so
//  one the partner had abandoned opened as a board, and finishing it sent a result into a dead
//  session.
//
//  Driven through the real stores with `PuzzleSessionBackend` replaced, and a queue held in memory
//  so nothing here reads or clears the file the deck-game suites use.
//

import Foundation
import Testing
@testable import Twofold

/// A session the tests can take offline, end, or have refuse a result. Refuses any result once
/// the session has ended, as the server does since 20261116000000.
@MainActor
final class FakePuzzleBackend: PuzzleSessionBackend {
    let me = UUID()
    let partner = UUID()
    var currentUserID: UUID? { me }

    var gameType: GameType
    var status: GameSessionStatus = .active
    var isOffline = false
    var isRefusing = false
    var difficulty: SudokuDifficulty?
    var theme: WordSearchTheme?
    let contentID = UUID()
    var responses: [GameResponse] = []

    private(set) var submitted: [(sessionID: UUID, answer: String)] = []
    private(set) var notified: [BackendService.CoupleNotificationEvent] = []

    init(gameType: GameType) {
        self.gameType = gameType
        switch gameType {
        case .sudoku: difficulty = .easy
        case .wordSearch: theme = WordSearchTheme.allCases.first
        default: break
        }
    }

    func fetchGameSession(id: UUID) async throws -> BackendService.GameSessionDetail {
        if isOffline { throw URLError(.notConnectedToInternet) }
        let session = GameSession(
            id: id, coupleID: UUID(), gameType: gameType, initiatorID: me, status: status,
            totalRounds: 1, isDaily: false, deckID: nil, startedAt: .now, completedAt: nil,
            createdAt: .now, updatedAt: .now
        )
        let round = GameSessionRound(
            id: UUID(), sessionID: id, roundNumber: 1, contentID: contentID,
            discussionStatus: nil, difficulty: difficulty, theme: theme
        )
        return BackendService.GameSessionDetail(session: session, rounds: [round], content: [:], responses: responses)
    }

    /// Awaited before a result lands, so a test can hold a send in the air.
    var beforeSubmit: (() async -> Void)?

    func submitGameResponse(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool?) async throws {
        await beforeSubmit?()
        if isOffline { throw URLError(.notConnectedToInternet) }
        // Stands in for the 42501 RLS answers with; `isPermanentRefusal` reads both the same.
        if isRefusing || status.hasEnded { throw BackendService.WriteAffectedNoRows() }
        submitted.append((sessionID, answerValue))
        responses.removeAll { $0.responderID == me }
        responses.append(GameResponse(
            id: UUID(), sessionID: sessionID, roundNumber: roundNumber, responderID: me,
            answerValue: answerValue, isCorrect: isCorrect, createdAt: .now
        ))
    }

    func notifyPartner(event: BackendService.CoupleNotificationEvent, detail: String?, sessionID: UUID, gameType: GameType) async {
        notified.append(event)
    }

    /// Whether a reminder reaches the server. Offline answers no regardless.
    var remindersDeliver = true
    private(set) var reminders: [String] = []

    func sendGameReminder(detail: String, sessionID: UUID, gameType: GameType) async -> Bool {
        reminders.append(detail)
        return remindersDeliver && !isOffline
    }
}

final class MemoryGameResponseQueue: GameResponseQueue {
    private(set) var items: [PendingGameResponse] = []

    func all() -> [PendingGameResponse] { items }
    func put(_ response: PendingGameResponse) {
        items.removeAll { $0.answersSameRound(as: response) }
        items.append(response)
    }
    func remove(id: UUID) { items.removeAll { $0.id == id } }
    func append(_ response: PendingGameResponse) { items.append(response) }
}

@MainActor
@Suite("A finished puzzle's result reaches the server", .serialized)
struct PuzzleResultDeliveryTests {

    /// A Word Guess board, loaded and won in one guess.
    private func finishedWordGuess(
        _ backend: FakePuzzleBackend,
        queue: MemoryGameResponseQueue
    ) async throws -> WordGuessGameStore {
        let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
        await store.load()
        #expect(store.phase == .ready)
        let word = try #require(store.answer)
        for letter in word { store.type(letter) }
        #expect(store.play?.isComplete == true)
        await store.retryPendingResult()  // waits for the first send to finish either way
        return store
    }

    @Test("a result that fails to send is kept, and the screen says it is waiting")
    func failedSendIsKept() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        let queue = MemoryGameResponseQueue()
        let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
        await store.load()
        backend.isOffline = true
        let word = try #require(store.answer)
        for letter in word { store.type(letter) }
        await store.retryPendingResult()

        #expect(backend.submitted.isEmpty)
        #expect(queue.items.count == 1, "The finished board's result was not kept anywhere it could be sent from")
        #expect(store.resultPending, "The screen would still say the result is saved")
    }

    @Test("the open screen sends it once the connection is back")
    func openScreenRetries() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        let queue = MemoryGameResponseQueue()
        let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
        await store.load()
        backend.isOffline = true
        for letter in try #require(store.answer) { store.type(letter) }
        await store.retryPendingResult()
        #expect(store.resultPending)

        backend.isOffline = false
        await store.retryPendingResult()

        #expect(backend.submitted.count == 1)
        #expect(queue.items.isEmpty)
        #expect(!store.resultPending)
        #expect(backend.notified == [.gamePartnerFinished], "The partner was never told the board was done")
    }

    @Test("with no screen open, the outbox sends it and tells the partner")
    func outboxSendsWithNoScreen() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        let queue = MemoryGameResponseQueue()
        do {
            let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
            await store.load()
            backend.isOffline = true
            for letter in try #require(store.answer) { store.type(letter) }
            await store.retryPendingResult()
        }
        #expect(queue.items.count == 1)

        backend.isOffline = false
        await GameResponseOutbox.flush(backend: backend, queue: queue, isLocalSession: { _ in false })

        #expect(backend.submitted.count == 1)
        #expect(queue.items.isEmpty)
        #expect(backend.notified == [.gamePartnerFinished])
    }

    @Test("the outbox says results are ready when the partner's is already in")
    func outboxSaysResultsReady() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        backend.responses = [GameResponse(
            id: UUID(), sessionID: UUID(), roundNumber: 1, responderID: backend.partner,
            answerValue: "theirs", isCorrect: true, createdAt: .now
        )]
        let queue = MemoryGameResponseQueue()
        queue.put(PendingGameResponse(
            sessionID: UUID(), roundNumber: 1, responderID: backend.me, answerValue: "mine",
            isCorrect: true, resultGameType: .wordGuess, resultNotifyDetail: "Word Guess"
        ))

        await GameResponseOutbox.flush(backend: backend, queue: queue, isLocalSession: { _ in false })

        #expect(backend.notified == [.gameResultsReady])
    }

    @Test("a solved Sudoku goes through the same queue")
    func sudokuIsQueuedToo() async throws {
        let backend = FakePuzzleBackend(gameType: .sudoku)
        let queue = MemoryGameResponseQueue()
        let store = SudokuGameStore(sessionID: UUID(), backend: backend, queue: queue)
        await store.load()
        #expect(store.phase == .ready)
        backend.isOffline = true
        // With nothing selected, each hint fills the first cell still wrong or empty.
        for _ in 0..<81 where store.play?.isComplete == false {
            store.selected = nil
            store.useHint()
        }
        #expect(store.play?.isComplete == true)
        await store.retryPendingResult()

        #expect(queue.items.count == 1)
        #expect(store.resultPending)

        backend.isOffline = false
        await store.retryPendingResult()
        #expect(backend.submitted.count == 1)
        #expect(!store.resultPending)
    }

    @Test("a refused result leaves the queue rather than being retried for ever")
    func refusedResultIsDropped() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        backend.isRefusing = true
        let queue = MemoryGameResponseQueue()
        let store = try await finishedWordGuess(backend, queue: queue)

        #expect(queue.items.isEmpty)
        #expect(!store.resultPending)
        #expect(backend.notified.isEmpty)
    }

    @Test("the outbox stops at a dropped connection and keeps what it could not send")
    func outboxStopsWhenOffline() async {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        backend.isOffline = true
        let queue = MemoryGameResponseQueue()
        for answer in ["a", "b"] {
            queue.append(PendingGameResponse(sessionID: UUID(), roundNumber: 1, responderID: backend.me, answerValue: answer, isCorrect: nil))
        }

        await GameResponseOutbox.flush(backend: backend, queue: queue, isLocalSession: { _ in false })

        #expect(queue.items.count == 2)
    }

    @Test("the outbox sends a deck answer but leaves one for a session started offline")
    func outboxLeavesLocalSessions() async {
        let backend = FakePuzzleBackend(gameType: .thisOrThat)
        let queue = MemoryGameResponseQueue()
        let local = UUID()
        queue.append(PendingGameResponse(sessionID: local, roundNumber: 1, responderID: backend.me, answerValue: "offline deck", isCorrect: nil))
        queue.append(PendingGameResponse(sessionID: UUID(), roundNumber: 2, responderID: backend.me, answerValue: "real deck", isCorrect: nil))

        await GameResponseOutbox.flush(backend: backend, queue: queue, isLocalSession: { $0 == local })

        #expect(backend.submitted.map(\.answer) == ["real deck"])
        #expect(queue.items.map(\.answerValue) == ["offline deck"])
        // A deck answer's push depends on the rest of the session, and stays with the deck screen.
        #expect(backend.notified.isEmpty)
    }

    @Test("the outbox drops an answer the server refuses and goes on to the next")
    func outboxDropsRefusals() async {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        backend.isRefusing = true
        let queue = MemoryGameResponseQueue()
        queue.append(PendingGameResponse(sessionID: UUID(), roundNumber: 1, responderID: backend.me, answerValue: "x", isCorrect: nil))
        queue.append(PendingGameResponse(sessionID: UUID(), roundNumber: 1, responderID: backend.me, answerValue: "y", isCorrect: nil))

        await GameResponseOutbox.flush(backend: backend, queue: queue, isLocalSession: { _ in false })

        #expect(queue.items.isEmpty)
    }
}

@MainActor
@Suite("A puzzle ended elsewhere shows as ended")
struct PuzzleEndedStateTests {

    @Test("opened after the partner abandoned it, each puzzle says it has ended", arguments: [
        GameSessionStatus.abandoned, .archived,
    ])
    func opensEnded(_ status: GameSessionStatus) async {
        for gameType in [GameType.sudoku, .wordGuess, .wordSearch] {
            let backend = FakePuzzleBackend(gameType: gameType)
            backend.status = status
            let queue = MemoryGameResponseQueue()
            let isEnded: Bool
            switch gameType {
            case .sudoku:
                let store = SudokuGameStore(sessionID: UUID(), backend: backend, queue: queue)
                await store.load()
                isEnded = store.phase == .ended
            case .wordGuess:
                let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
                await store.load()
                isEnded = store.phase == .ended
            default:
                let store = WordSearchGameStore(sessionID: UUID(), backend: backend, queue: queue)
                await store.load()
                isEnded = store.phase == .ended
            }
            #expect(isEnded, "\(gameType) opened a \(status) session as a playable board")
        }
    }

    @Test("a board ended while it is open becomes ended on the next read")
    func endsWhileOpen() async {
        let backend = FakePuzzleBackend(gameType: .wordSearch)
        let store = WordSearchGameStore(sessionID: UUID(), backend: backend, queue: MemoryGameResponseQueue())
        await store.load()
        #expect(store.phase == .ready)

        backend.status = .abandoned
        await store.retryPendingResult()

        #expect(store.phase == .ended)
    }

    @Test("a result finished offline into a session abandoned meanwhile is dropped, and the board ends")
    func pendingResultIntoEndedSession() async throws {
        let backend = FakePuzzleBackend(gameType: .wordGuess)
        let queue = MemoryGameResponseQueue()
        let store = WordGuessGameStore(sessionID: UUID(), backend: backend, queue: queue)
        await store.load()
        backend.isOffline = true
        for letter in try #require(store.answer) { store.type(letter) }
        await store.retryPendingResult()
        #expect(queue.items.count == 1)

        backend.isOffline = false
        backend.status = .abandoned
        await store.retryPendingResult()

        #expect(store.phase == .ended)
        #expect(queue.items.isEmpty)
        #expect(!store.resultPending)
        #expect(backend.submitted.isEmpty)
        #expect(backend.notified.isEmpty)
    }

    @Test("a completed session is not an ended one")
    func completedIsNotEnded() async {
        let backend = FakePuzzleBackend(gameType: .sudoku)
        backend.status = .completed
        let store = SudokuGameStore(sessionID: UUID(), backend: backend, queue: MemoryGameResponseQueue())
        await store.load()
        #expect(store.phase == .ready)
    }
}

@Suite("Puzzle results in the answer queue")
struct PendingPuzzleResultStoreTests {

    @Test("a newer result to the same round replaces the older one")
    func putReplaces() {
        LocalGameSessionTestLock.withExclusiveStores {
            let session = UUID(), me = UUID()
            PendingGameResponseStore.put(PendingGameResponse(sessionID: session, roundNumber: 1, responderID: me, answerValue: "first", isCorrect: nil))
            PendingGameResponseStore.put(PendingGameResponse(sessionID: session, roundNumber: 1, responderID: me, answerValue: "second", isCorrect: true, resultGameType: .sudoku))
            PendingGameResponseStore.put(PendingGameResponse(sessionID: UUID(), roundNumber: 1, responderID: me, answerValue: "other", isCorrect: nil))

            let all = PendingGameResponseStore.all()
            #expect(all.map(\.answerValue).sorted() == ["other", "second"])
            #expect(all.first { $0.answerValue == "second" }?.resultGameType == .sudoku)
        }
    }

    @Test("answers queued before results carried a game type still decode")
    func olderEntriesDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sessionID":"\(UUID().uuidString)","roundNumber":1,\
        "responderID":"\(UUID().uuidString)","answerValue":"blue","queuedAt":760000000}
        """
        let decoded = try JSONDecoder().decode(PendingGameResponse.self, from: Data(json.utf8))
        #expect(decoded.resultGameType == nil)
        #expect(decoded.resultNotifyDetail == nil)
    }
}
