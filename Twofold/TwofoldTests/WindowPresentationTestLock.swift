//
//  WindowPresentationTestLock.swift
//  TwofoldTests
//
//  Exclusive access to the app's window and presentation stack.
//
//  Same reason `LocalGameSessionTestLock` and `WidgetSnapshotTestLock` exist: `@Suite(.serialized)`
//  only orders tests *within* one suite, and four suites here drive process-global UIKit state.
//  `AppearancePreferenceTests`, `DrawingCanvasSizeTests`, `PanelSwapTests` and
//  `SheetDetentWidthTests` each stand up a `UIWindow`, make it key, and present or restyle a view
//  controller on it. There is one key window and one presentation hierarchy per process, so run
//  two of those at once and they present onto each other's stack.
//
//  What that looked like: `PanelSwapTests`' negative control — the one asserting `sheet(item:)`
//  rebuilds its panel — reported that the panel had *survived*, and said so in a message blaming
//  SwiftUI for having changed. Green on its own, red in a full run. It was read as a slow machine
//  and given a longer deadline first; that fixed `AppearancePreferenceTests`, which is serialized
//  and so was only ever fighting the other three, and did nothing here, because no amount of
//  waiting helps when another suite is dismissing what you are waiting on.
//
//  An async lock rather than `NSLock`, because unlike the stores those tests guard, this work
//  suspends: presentation, trait propagation and dismissal are all awaited. A plain mutex cannot
//  be held across an `await`, and an `actor` alone will not do it either — actors are reentrant,
//  so a second caller enters at the first suspension point. Hence the explicit queue.
//

import Foundation

actor WindowPresentationTestLock {
    static let shared = WindowPresentationTestLock()

    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` with nothing else touching the window or presentation stack.
    static func withExclusiveWindow<T>(_ body: () async throws -> T) async rethrows -> T {
        await shared.acquire()
        defer { Task { await shared.release() } }
        return try await body()
    }

    private func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isHeld = false
        } else {
            // Stays held, handed straight to the next waiter — clearing the flag first would let a
            // fresh caller barge in ahead of a queue that has been waiting.
            waiting.removeFirst().resume()
        }
    }
}
