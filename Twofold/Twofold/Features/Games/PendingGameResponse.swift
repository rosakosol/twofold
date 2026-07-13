//
//  PendingGameResponse.swift
//  Twofold
//
//  Local queue for game answers submitted while offline — GameSessionStore.submit() writes here
//  (and applies the same response optimistically in memory) instead of losing the tap, and
//  GameSessionStore.syncPendingResponses() drains it in order once connectivity returns.
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

    init(id: UUID = UUID(), sessionID: UUID, roundNumber: Int, responderID: UUID, answerValue: String, isCorrect: Bool?, queuedAt: Date = .now) {
        self.id = id
        self.sessionID = sessionID
        self.roundNumber = roundNumber
        self.responderID = responderID
        self.answerValue = answerValue
        self.isCorrect = isCorrect
        self.queuedAt = queuedAt
    }
}

enum PendingGameResponseStore {
    private static let key = "pendingGameResponses"

    static func all() -> [PendingGameResponse] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingGameResponse].self, from: data)) ?? []
    }

    static func forSession(_ sessionID: UUID) -> [PendingGameResponse] {
        all().filter { $0.sessionID == sessionID }.sorted { $0.queuedAt < $1.queuedAt }
    }

    static func add(_ response: PendingGameResponse) {
        save(all() + [response])
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    private static func save(_ responses: [PendingGameResponse]) {
        guard let data = try? JSONEncoder().encode(responses) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
