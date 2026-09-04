//
//  LocalGameSessionTestLock.swift
//  TwofoldTests
//
//  Exclusive access to the two `UserDefaults` keys behind offline game play — the local sessions
//  and the queued answers.
//
//  Same reason `WidgetSnapshotTestLock` exists: `@Suite(.serialized)` only orders tests *within*
//  one suite, and two suites here write and clear the same process-global state.
//  `LocalGameSessionTests` and `GameSessionStoreOfflineTests` running in parallel cleared each
//  other's fixtures mid-test — a session created a line earlier came back nil.
//

import Foundation
@testable import Twofold

enum LocalGameSessionTestLock {
    private static let lock = NSLock()

    /// Runs `body` with exclusive access, and always clears both stores afterwards so the next
    /// holder starts from a known state whatever `body` did.
    static func withExclusiveStores<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer {
            LocalGameSessionStore.clear()
            PendingGameResponseStore.clear()
            lock.unlock()
        }
        LocalGameSessionStore.clear()
        PendingGameResponseStore.clear()
        return try body()
    }
}
