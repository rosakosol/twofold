//
//  SignOutRaceTests.swift
//  TwofoldTests
//
//  Work that was already in the air when somebody signed out (CORE-4), and the order sign-out
//  tears things down in (CORE-9).
//
//  A couple fetch, an outbox pass or a widget refresh started before sign-out used to finish after
//  it as if nothing had happened: the fetch brought the previous couple back on screen, the
//  widget refresh wrote their names into the app group after it had been cleared, and the outbox
//  pass held its "already sending" flag so the next account's own edits were not sent. Each test
//  holds one of those in the air, signs out underneath it, and lets it land.
//
//  Nested under `PendingMemoryDiskTests` because these write to `PendingWriteStore`, which the
//  suites there also clear.
//

import ActivityKit
import Foundation
import Testing
@testable import Twofold

/// Holds whoever waits on it until `open()`.
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    /// Returns once somebody is waiting, or after about five seconds.
    func untilSomeoneArrives() async {
        for _ in 0..<500 where arrivals == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Records the order sign-out calls things in.
final class FakeSessionTeardown: SessionTeardown {
    private(set) var calls: [String] = []

    func unregisterDeviceToken(_ tokenHex: String) async throws { calls.append("unregisterDeviceToken") }
    func endLiveActivities() async { calls.append("endLiveActivities") }
    func signOut() async throws { calls.append("signOut") }
    func deleteAccount() async throws { calls.append("deleteAccount") }
    func resetGameResponseOutbox() { calls.append("resetGameResponseOutbox") }
}

/// Answers requests to `held.twofold.invalid` only when told to, so a test can keep a download in
/// the air. Registered for the one test that needs it.
final class HeldURLProtocol: URLProtocol {
    static let host = "held.twofold.invalid"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var held: [HeldURLProtocol] = []

    static var heldCount: Int { lock.withLock { held.count } }

    static func releaseAll() {
        let all = lock.withLock { defer { held = [] }; return held }
        for request in all { request.respond() }
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.withLock { Self.held.append(self) } }
    override func stopLoading() {}

    private func respond() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0xFF, 0xD8, 0xFF]))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class WrittenSnapshots {
    var items: [WidgetSnapshot] = []
}

extension PendingMemoryDiskTests {
    @Suite("Work in the air at sign-out does not outlive it", .serialized)
    @MainActor
    struct SignOutRaceTests {

        private func pairedCouple() -> Couple {
            Couple(
                partnerA: Person(name: "Alex", accentColor: Person.palette[1]),
                partnerB: Person(name: "Sam", accentColor: Person.palette[0]),
                startedDatingOn: .now
            )
        }

        private func pairedState(_ couple: Couple) -> BackendService.CoupleState {
            BackendService.CoupleState(
                couple: couple,
                trips: [],
                memories: [],
                flights: [],
                subscriptionActive: true,
                viewerSubscriptionActive: true,
                subscriptionTier: "plus",
                viewerSubscriptionStore: nil,
                partnerConnectedCelebrationShown: true,
                setupChecklistDismissed: true
            )
        }

        // MARK: - CORE-4

        @Test("a couple fetched before sign-out is not adopted after it")
        func adoptAfterSignOut() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            model.backend = FakeCoupleDataBackend()
            model.hasCouple = true
            let gate = Gate()
            let state = pairedState(pairedCouple())
            model.fetchCoupleStateOutcome = {
                await gate.wait()
                return .paired(state)
            }

            let refresh = Task { await model.refreshCoupleStateIfNeeded() }
            await gate.untilSomeoneArrives()
            // What sign-out does to the in-memory half.
            model.resetAccountScopedState()
            gate.open()
            await refresh.value

            #expect(!model.hasCouple, "the signed-out user was put back in the previous couple's app")
            #expect(model.backendCoupleID == nil)
            #expect(model.partner.name != "Sam", "the previous partner's name is back on screen")
        }

        @Test("an outbox pass still sending at sign-out does not stop the next account's being sent")
        func outboxPassAcrossSignOut() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            let backend = FakeCoupleDataBackend()
            model.backend = backend
            model.setBackendCoupleIDForTesting(UUID())
            let gate = Gate()
            backend.beforeUpdateFirstName = { await gate.wait() }
            PendingWriteStore.add(.firstName("Previous account"))

            let previousPass = Task { await model.syncPendingWrites() }
            await gate.untilSomeoneArrives()

            // Signed out, and somebody else signed in and edited their name.
            model.resetAccountScopedState()
            PendingWriteStore.clear()
            model.setBackendCoupleIDForTesting(UUID())
            backend.beforeUpdateFirstName = nil
            PendingWriteStore.add(.firstName("Next account"))
            await model.syncPendingWrites()

            #expect(backend.firstNames.contains("Next account"), "the next account's edit waited on the previous account's pass")

            gate.open()
            await previousPass.value
            #expect(backend.firstNames.filter { $0 == "Next account" }.count == 1, "sent twice")
        }

        @Test("a widget refresh that outlives sign-out writes nothing back")
        func widgetRefreshAcrossSignOut() async {
            URLProtocol.registerClass(HeldURLProtocol.self)
            defer { URLProtocol.unregisterClass(HeldURLProtocol.self) }
            let model = AppModel()
            model.partnerConnected = true
            model.couple = pairedCouple()
            model.couple.partnerA.avatarURL = URL(string: "https://\(HeldURLProtocol.host)/me.jpg")
            let written = WrittenSnapshots()

            let refresh = Task { await WidgetSnapshotWriter.refresh(appModel: model) { written.items.append($0) } }
            for _ in 0..<500 where HeldURLProtocol.heldCount == 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(written.items.count == 1, "precondition: the local half is written before any download")

            model.resetAccountScopedState()
            HeldURLProtocol.releaseAll()
            await refresh.value

            #expect(written.items.count == 1, "the signed-out account's names were written back into the widgets")
        }

        // MARK: - CORE-9

        @Test("sign-out ends Live Activities while the session they need still exists")
        func liveActivitiesEndBeforeSignOut() async {
            let model = AppModel()
            let teardown = FakeSessionTeardown()
            model.sessionTeardown = teardown

            await model.signOut()

            let ended = teardown.calls.firstIndex(of: "endLiveActivities")
            let signedOut = teardown.calls.firstIndex(of: "signOut")
            #expect(ended != nil && signedOut != nil)
            #expect((ended ?? .max) < (signedOut ?? .min), "ended after the session was gone, so the server's token rows were never ended: \(teardown.calls)")
            #expect(teardown.calls.contains("resetGameResponseOutbox"), "a game result in the air outlived the account")
        }

        @Test("deleting the account ends Live Activities before the account goes")
        func liveActivitiesEndBeforeDeletion() async throws {
            let model = AppModel()
            let teardown = FakeSessionTeardown()
            model.sessionTeardown = teardown

            try await model.deleteAccount()

            let ended = teardown.calls.firstIndex(of: "endLiveActivities")
            let deleted = teardown.calls.firstIndex(of: "deleteAccount")
            #expect((ended ?? .max) < (deleted ?? .min), "\(teardown.calls)")
        }
    }
}

@MainActor
@Suite("Ending every Live Activity", .serialized)
struct LiveActivityEndAllTests {

    /// The case sign-out missed: a card started by an earlier run of the app, which this run's
    /// manager has never been told about because no flight refresh has reconciled it yet.
    @Test(
        "ending all ends a card this run of the app did not start",
        .enabled(if: ActivityAuthorizationInfo().areActivitiesEnabled)
    )
    func endsCardsFromAnEarlierRun() async throws {
        let attributes = JourneyActivityAttributes(
            flightID: UUID(),
            travelerName: "Alex",
            partnerName: "Sam",
            viewerIsTraveler: true,
            flightNumber: "UA60",
            airlineName: "United",
            originCode: "SFO",
            originCity: "San Francisco",
            destinationCode: "MEL",
            destinationCity: "Melbourne"
        )
        let content = ActivityContent(
            state: JourneyActivityAttributes.ContentState(status: "scheduled", progress: 0, isReunion: false),
            staleDate: nil
        )
        let activity = try Activity<JourneyActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
        defer { Task { await activity.end(nil, dismissalPolicy: .immediate) } }

        await LiveActivityManager.shared.endAll()

        #expect(
            !Activity<JourneyActivityAttributes>.activities.contains { $0.id == activity.id && $0.activityState == .active },
            "the previous run's card is still on the Lock Screen after sign-out"
        )
    }
}

extension PuzzleResultDeliveryTests {
    /// In this suite because the outbox's in-flight state is shared by every flush.
    @Test("a result still sending at sign-out neither blocks the next account's nor pushes afterwards")
    func outboxFlushAcrossSignOut() async {
        let gate = Gate()
        let previous = FakePuzzleBackend(gameType: .wordGuess)
        previous.beforeSubmit = { await gate.wait() }
        let previousQueue = MemoryGameResponseQueue()
        previousQueue.append(PendingGameResponse(
            sessionID: UUID(), roundNumber: 1, responderID: previous.me, answerValue: "a", isCorrect: true,
            resultGameType: .wordGuess, resultNotifyDetail: "Word Guess"
        ))
        let previousFlush = Task {
            await GameResponseOutbox.flush(backend: previous, queue: previousQueue, isLocalSession: { _ in false })
        }
        await gate.untilSomeoneArrives()

        // What sign-out calls.
        LiveSessionTeardown().resetGameResponseOutbox()

        let next = FakePuzzleBackend(gameType: .wordGuess)
        let nextQueue = MemoryGameResponseQueue()
        nextQueue.append(PendingGameResponse(sessionID: UUID(), roundNumber: 1, responderID: next.me, answerValue: "b", isCorrect: true))
        await GameResponseOutbox.flush(backend: next, queue: nextQueue, isLocalSession: { _ in false })
        #expect(next.submitted.map(\.answer) == ["b"], "the next account's result waited on the previous account's flush")

        gate.open()
        await previousFlush.value
        #expect(previous.notified.isEmpty, "pushed the previous account's partner after sign-out")
    }
}
