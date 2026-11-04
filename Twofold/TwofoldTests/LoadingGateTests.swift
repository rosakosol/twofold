//
//  LoadingGateTests.swift
//  TwofoldTests
//
//  The memory detail screen and the Memories map now hold themselves back until their pieces are
//  ready, so they appear once rather than assembling in front of the person. The danger in that is
//  the opposite failure — a screen that waits forever on one slow photo or a map with no network —
//  so what is pinned here is mostly the timeout: that it fires, that it does not fire early, and
//  that the work it gave up waiting for still lands.
//

import Foundation
import Testing
@testable import Twofold

@MainActor
struct LoadingGateTests {

    @Test("work that finishes inside the timeout is ready")
    func fastWorkIsReady() async {
        var ran = false
        let outcome = await LoadingGate.wait(upTo: .seconds(5)) {
            ran = true
        }
        #expect(outcome == .ready)
        #expect(ran)
    }

    @Test("work that outlasts the timeout stops holding the screen back")
    func slowWorkTimesOut() async {
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await LoadingGate.wait(upTo: .milliseconds(100)) {
            try? await Task.sleep(for: .seconds(10))
        }
        #expect(outcome == .timedOut)
        // Well short of the work's ten seconds: the gate returned on its own timeout.
        #expect(clock.now - start < .seconds(3))
    }

    /// The screen shows on the timeout with the photo's placeholder, and the photo is meant to
    /// arrive into it — which needs the download to carry on rather than being cancelled.
    @Test("work keeps running after the timeout")
    func workContinuesAfterTimeout() async throws {
        var finished = false
        let outcome = await LoadingGate.wait(upTo: .milliseconds(50)) {
            try? await Task.sleep(for: .milliseconds(300))
            finished = true
        }
        #expect(outcome == .timedOut)
        #expect(!finished)

        try await Task.sleep(for: .milliseconds(1500))
        #expect(finished, "the work was cancelled when the gate stopped waiting for it")
    }

    /// The caller's own task being cancelled — the screen dismissed mid-load — must not strand
    /// it: the gate still returns, on the timeout at the latest.
    @Test("a cancelled caller still gets an answer")
    func cancelledCallerReturns() async {
        let waiter = Task {
            await LoadingGate.wait(upTo: .milliseconds(200)) {
                try? await Task.sleep(for: .seconds(10))
            }
        }
        waiter.cancel()
        let outcome = await waiter.value
        #expect(outcome == .timedOut)
    }

    @Test("the detail screen gives up on its photo within a few seconds")
    func detailTimeoutIsBounded() {
        #expect(MemoryDetailView.photoWait <= .seconds(3))
    }
}
