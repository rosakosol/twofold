//
//  PendingGameResponse.swift
//  Twofold
//
//  Local queue for game answers submitted while offline — GameSessionStore.submit() writes here
//  (and applies the same response optimistically in memory) instead of losing the tap, and
//  GameSessionStore.syncPendingResponses() drains it in order once connectivity returns.
//  A generated puzzle's one result is queued here too, before it is sent (`PuzzleResult`), and
//  `GameResponseOutbox` drains whatever is left at launch, on foreground and on reconnect, with
//  no game screen open.
//  Main-app only, plain UserDefaults — nothing outside this process ever touches it, so there's
//  no need for the App Group storage the widget/share-extension hand-off structs use.
//

import Foundation

struct PendingGameResponse: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let roundNumber: Int
    let responderID: UUID
    let answerValue: String
    let isCorrect: Bool?
    let queuedAt: Date
    /// Which question was answered, independent of where it sat in this session's round order.
    ///
    /// Only meaningful for a game started offline (`LocalGameSession`), where the round numbers
    /// are the app's own: `start_deck_session` orders its rounds with an unordered `array_agg`, so
    /// the real session's round 3 need not hold the question answered as round 3 on the plane.
    /// `LocalGameSessionSync` matches on this instead. Optional so answers queued by an older
    /// build — which are all for real sessions, where the round number is already correct — still
    /// decode.
    let contentID: UUID?
    /// Set only for a generated puzzle's one result (`PuzzleResult`), where sending it *is*
    /// finishing: `GameResponseOutbox` sends the partner the same push the puzzle screen would
    /// have, had it still been open when the result landed. Nil for a deck answer, whose push
    /// depends on what else the session holds and is left to `GameSessionStore`.
    let resultGameType: GameType?
    /// What that push calls the puzzle — "Hard Sudoku" — when `resultGameType` is set.
    let resultNotifyDetail: String?

    init(id: UUID = UUID(), sessionID: UUID, roundNumber: Int, responderID: UUID, answerValue: String, isCorrect: Bool?, contentID: UUID? = nil, resultGameType: GameType? = nil, resultNotifyDetail: String? = nil, queuedAt: Date = .now) {
        self.id = id
        self.sessionID = sessionID
        self.roundNumber = roundNumber
        self.responderID = responderID
        self.answerValue = answerValue
        self.isCorrect = isCorrect
        self.contentID = contentID
        self.resultGameType = resultGameType
        self.resultNotifyDetail = resultNotifyDetail
        self.queuedAt = queuedAt
    }

    /// Whether this answers the same round, for the same person, as `other` — the key the
    /// server's upsert uses, so only the newer of two such answers is worth sending.
    func answersSameRound(as other: PendingGameResponse) -> Bool {
        sessionID == other.sessionID && roundNumber == other.roundNumber && responderID == other.responderID
    }
}

enum PendingGameResponseStore {
    private static let key = "pendingGameResponses"

    /// A file rather than `UserDefaults.standard`.
    ///
    /// These are free-text answers to the intimate questions the app is built around, queued
    /// offline. A preferences plist cannot take a protection class — cfprefsd owns the file — so
    /// for as long as they lived there they sat at CompleteUntilFirstUserAuthentication and in
    /// every backup, whatever the rest of the app did. Here they can be at Complete like the other
    /// drafted content.
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("PendingGameResponses.json")
    }

    static func all() -> [PendingGameResponse] {
        if let data = try? Data(contentsOf: fileURL) {
            return (try? JSONDecoder().decode([PendingGameResponse].self, from: data)) ?? []
        }
        // One-time read-through of the old location. An answer queued offline and not yet
        // submitted is the user's words, so losing it on update is not acceptable.
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let migrated = (try? JSONDecoder().decode([PendingGameResponse].self, from: data)) ?? []
        if !migrated.isEmpty { save(migrated) }
        UserDefaults.standard.removeObject(forKey: key)
        return migrated
    }

    static func forSession(_ sessionID: UUID) -> [PendingGameResponse] {
        all().filter { $0.sessionID == sessionID }.sorted { $0.queuedAt < $1.queuedAt }
    }

    static func add(_ response: PendingGameResponse) {
        save(all() + [response])
    }

    /// Queues `response` in place of any older answer to the same round. For a puzzle's result,
    /// which is resent whole rather than appended to.
    static func put(_ response: PendingGameResponse) {
        save(all().filter { !$0.answersSameRound(as: response) } + [response])
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    /// Signing out has to take these with it. `submitGameResponse` writes as whoever is signed in
    /// *now*, not as the `responderID` the answer was queued under — so answers left behind by one
    /// account would be submitted, on the next reconnect, as the next person to sign in on this
    /// device.
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        // And the old key, for an install that signed out before anything read the queue across
        // the update.
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ responses: [PendingGameResponse]) {
        guard let data = try? JSONEncoder().encode(responses) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
