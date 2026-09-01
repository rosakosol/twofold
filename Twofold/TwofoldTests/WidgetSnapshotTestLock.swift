//
//  WidgetSnapshotTestLock.swift
//  TwofoldTests
//
//  `WidgetSnapshot` is a single app-group UserDefaults key — process-wide global state. Swift
//  Testing runs suites in parallel, and `.serialized` only orders tests *within* one suite, so two
//  suites that both write and clear that key interleave and clear each other's fixtures mid-test.
//  That reports as a failure in whichever one lost the race, with nothing wrong in the code under
//  test: it passes alone and fails in the full run.
//
//  Every test that touches the snapshot takes this lock instead.
//

import Foundation
@testable import Twofold

enum WidgetSnapshotTestLock {
    private static let lock = NSLock()

    /// Runs `body` with exclusive access to the snapshot, and always clears it afterwards so the
    /// next holder starts from a known state whatever `body` did.
    static func withExclusiveSnapshot<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer {
            WidgetSnapshot.clear()
            lock.unlock()
        }
        return try body()
    }

    /// Async variant, for the `EntityQuery` calls that back the widget pickers.
    static func withExclusiveSnapshot<T>(_ body: () async throws -> T) async rethrows -> T {
        lock.lock()
        defer {
            WidgetSnapshot.clear()
            lock.unlock()
        }
        return try await body()
    }
}
