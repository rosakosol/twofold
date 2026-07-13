//
//  GameIntroSeenStore.swift
//  Twofold
//
//  The intro screen's job is explaining the async answer-then-reveal mechanic once — after a
//  player has seen it for a given game type (or a given deck), later sessions skip straight to
//  play. Device-local via UserDefaults, same pattern as ReviewPromptService's one-shot flags —
//  this is "have I personally seen this explanation," not couple-shared state, so it doesn't
//  need a backend round-trip.
//

import Foundation

enum GameIntroSeenStore {
    private static func key(for identifier: String) -> String { "gameIntro.seen.\(identifier)" }

    static func hasSeen(_ identifier: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: identifier))
    }

    static func markSeen(_ identifier: String) {
        UserDefaults.standard.set(true, forKey: key(for: identifier))
    }
}
