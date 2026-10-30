//
//  DeckGameBackButtonTests.swift
//  TwofoldTests
//
//  The four deck games hide the system back button and draw their own. A notification opens a
//  game inside `RootView`'s `fullScreenCover`, at the root of a fresh `NavigationStack`, where the
//  system button does not exist at all — so whatever the custom button is, it has to be there in
//  every state the screen can show. It used to be withheld in the error and abandoned states, both
//  reachable from a push (offline, or a session `leave_couple` abandoned after the reminder was
//  sent), and the screen had no way out but force-quitting.
//
//  `GameSessionStore.backButtonAction(myID:)` is what all four views read for that button.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct DeckGameBackButtonTests {

    private let me = UUID()

    private func store(status: GameSessionStatus, rounds: Int = 3, answered: Int = 0) -> GameSessionStore {
        let store = GameSessionStore()
        let id = UUID()
        let now = Date()
        store.session = GameSession(
            id: id, coupleID: UUID(), gameType: .thisOrThat, initiatorID: me, status: status,
            totalRounds: rounds, isDaily: false, deckID: UUID(), startedAt: now, completedAt: nil,
            createdAt: now, updatedAt: now
        )
        store.responses = (0..<answered).map { index in
            GameResponse(
                id: UUID(), sessionID: id, roundNumber: index + 1, responderID: me,
                answerValue: "a", isCorrect: nil, createdAt: now
            )
        }
        return store
    }

    // MARK: - The states that used to have no button

    @Test("a session that failed to load before anything arrived still has a way out")
    func errorBeforeLoad() {
        let store = GameSessionStore()
        store.errorMessage = "The Internet connection appears to be offline."
        #expect(store.backButtonAction(myID: me) == .leave)
    }

    @Test("an error over a half-played session leaves rather than stepping back a round")
    func errorMidRound() {
        let store = store(status: .active, answered: 1)
        store.errorMessage = "Something went wrong."
        #expect(store.backButtonAction(myID: me) == .leave)
    }

    @Test("an abandoned session has a way out", arguments: [0, 1, 3])
    func abandoned(answered: Int) {
        let store = store(status: .abandoned, answered: answered)
        #expect(store.backButtonAction(myID: me) == .leave)
    }

    // MARK: - The states that already worked, pinned so the fix does not move them

    @Test("still answering goes through the in-round back")
    func stillAnswering() {
        #expect(store(status: .active, answered: 0).backButtonAction(myID: me) == .inRound)
        #expect(store(status: .active, answered: 2).backButtonAction(myID: me) == .inRound)
    }

    @Test("before the session has loaded, back is the in-round one, which dismisses when nothing is answered")
    func loading() {
        let store = GameSessionStore()
        store.isLoading = true
        #expect(store.backButtonAction(myID: me) == .inRound)
    }

    @Test("done with my rounds, back closes the screen")
    func doneWithMyRounds() {
        #expect(store(status: .waitingForPartner, answered: 3).backButtonAction(myID: me) == .leave)
        #expect(store(status: .completed, answered: 3).backButtonAction(myID: me) == .leave)
    }

    @Test("editing a finished deck goes through the in-round back")
    func editingAnswers() {
        let store = store(status: .completed, answered: 3)
        store.viewingRoundNumber = 2
        #expect(store.backButtonAction(myID: me) == .inRound)
    }
}
