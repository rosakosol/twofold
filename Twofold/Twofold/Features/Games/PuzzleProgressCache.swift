//
//  PuzzleProgressCache.swift
//  Twofold
//
//  A half-finished puzzle, kept on the device.
//
//  Deliberately not `PendingGameResponseStore`. That queue appends every answer and drains them in
//  order, which is right for a game where each round's answer is its own fact. A generated puzzle
//  produces a new state on every tap, all of them describing the same one round — queued, they
//  would pile up hundreds deep and then replay the puzzle keystroke by keystroke. Only the newest
//  matters, so this replaces in place.
//
//  Stores the encoded string and nothing else. Decoding needs the puzzle it belongs to — a grid for
//  sudoku, a word for Word Guess — which is the caller's business and not something a cache should
//  have to know.
//
//  Keyed by responder as well as session, for the reason `PendingGameResponseStore.clear()` spells
//  out: anything left here by one account would otherwise be picked up by the next person to sign
//  in on this device — here, as their half-finished puzzle.
//

import Foundation

/// One game's worth of saved progress. The namespace is the `UserDefaults` key, so each game's
/// states are separate and, more to the point, sudoku's existing key is untouched — there are
/// half-solved grids sitting under it on real devices right now.
struct PuzzleProgressCache {
    let namespace: String

    static let sudoku = PuzzleProgressCache(namespace: "sudokuProgress")
    static let wordGuess = PuzzleProgressCache(namespace: "wordGuessProgress")

    /// Every namespace there is, for `clear()` on sign-out. A game whose cache is not listed here
    /// leaks one account's puzzle into the next account to use the device.
    static let all: [PuzzleProgressCache] = [.sudoku, .wordGuess]

    private struct Entry: Codable {
        var sessionID: UUID
        var responderID: UUID
        var encoded: String
        var savedAt: Date
    }

    func save(_ encoded: String, sessionID: UUID, responderID: UUID) {
        var entries = read().filter { !($0.sessionID == sessionID && $0.responderID == responderID) }
        entries.append(Entry(sessionID: sessionID, responderID: responderID, encoded: encoded, savedAt: .now))
        write(entries)
    }

    func load(sessionID: UUID, responderID: UUID) -> String? {
        read().first { $0.sessionID == sessionID && $0.responderID == responderID }?.encoded
    }

    func remove(sessionID: UUID, responderID: UUID) {
        write(read().filter { !($0.sessionID == sessionID && $0.responderID == responderID) })
    }

    /// Signing out takes these with it, exactly as the pending-answer queue does.
    static func clearAll() {
        for cache in all { UserDefaults.standard.removeObject(forKey: cache.namespace) }
    }

    private func read() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: namespace) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func write(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: namespace)
    }
}
