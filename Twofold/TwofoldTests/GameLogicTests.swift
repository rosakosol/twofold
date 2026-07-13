//
//  GameLogicTests.swift
//  TwofoldTests
//
//  Unit tests for the pure decision logic behind Couple Games — reveal/waiting-state
//  derivation, trivia scoring, match counting, and discussion completion. RLS/authorization
//  itself isn't testable here (no local Postgres harness in this repo); those guarantees are
//  verified manually against the live project post-migration, see the games feature summary.
//

import Testing
import Foundation
@testable import Twofold

struct GameLogicTests {

    private func makeResponse(round: Int, responder: UUID, value: String, isCorrect: Bool? = nil) -> GameResponse {
        GameResponse(id: UUID(), sessionID: UUID(), roundNumber: round, responderID: responder, answerValue: value, isCorrect: isCorrect, createdAt: .now)
    }

    private func makeRound(session: UUID = UUID(), number: Int, content: UUID = UUID(), discussionStatus: DiscussionRoundStatus? = nil) -> GameSessionRound {
        GameSessionRound(id: UUID(), sessionID: session, roundNumber: number, contentID: content, discussionStatus: discussionStatus)
    }

    // MARK: - Independent per-partner progress

    @Test func partnerProgressNotStartedWithZeroResponses() {
        let partner = UUID()
        #expect(GameLogic.partnerProgress(responses: [], partnerID: partner, totalRounds: 5) == .notStarted)
    }

    @Test func partnerProgressInProgressWithSomeRoundsAnswered() {
        let partner = UUID()
        let responses = [
            makeResponse(round: 1, responder: partner, value: "A"),
            makeResponse(round: 2, responder: partner, value: "B"),
        ]
        #expect(GameLogic.partnerProgress(responses: responses, partnerID: partner, totalRounds: 5) == .inProgress(answered: 2, total: 5))
    }

    @Test func partnerProgressFinishedOnceAllRoundsAnswered() {
        let partner = UUID()
        let responses = (1...5).map { makeResponse(round: $0, responder: partner, value: "A") }
        #expect(GameLogic.partnerProgress(responses: responses, partnerID: partner, totalRounds: 5) == .finished)
    }

    // MARK: - Travel Trivia Battle scoring

    @Test func triviaScoreCountsOnlyCorrectAnswersForThatResponder() {
        let me = UUID()
        let partner = UUID()
        let responses = [
            makeResponse(round: 1, responder: me, value: "Rome", isCorrect: true),
            makeResponse(round: 2, responder: me, value: "Paris", isCorrect: false),
            makeResponse(round: 3, responder: me, value: "Tokyo", isCorrect: true),
            makeResponse(round: 1, responder: partner, value: "Rome", isCorrect: true),
        ]
        #expect(GameLogic.triviaScore(responses: responses, responderID: me) == 2)
        #expect(GameLogic.triviaScore(responses: responses, responderID: partner) == 1)
    }

    @Test func triviaOutcomeDeclaresHigherScorerWinner() {
        let a = UUID()
        let b = UUID()
        let responses = [
            makeResponse(round: 1, responder: a, value: "x", isCorrect: true),
            makeResponse(round: 1, responder: b, value: "y", isCorrect: false),
        ]
        #expect(GameLogic.triviaOutcome(responses: responses, partnerAID: a, partnerBID: b) == .winner(a))
    }

    @Test func triviaOutcomeIsTieOnEqualScores() {
        let a = UUID()
        let b = UUID()
        let responses = [
            makeResponse(round: 1, responder: a, value: "x", isCorrect: true),
            makeResponse(round: 1, responder: b, value: "y", isCorrect: true),
        ]
        #expect(GameLogic.triviaOutcome(responses: responses, partnerAID: a, partnerBID: b) == .tie)
    }

    @Test func triviaOutcomeTieWhenNeitherHasAnswered() {
        let a = UUID()
        let b = UUID()
        #expect(GameLogic.triviaOutcome(responses: [], partnerAID: a, partnerBID: b) == .tie)
    }

    // MARK: - Who's More Likely To / This or That matching

    @Test func matchCountOnlyCountsRoundsWhereBothAnsweredTheSameValue() {
        let session = UUID()
        let a = UUID()
        let b = UUID()
        let rounds = [makeRound(session: session, number: 1), makeRound(session: session, number: 2), makeRound(session: session, number: 3)]
        let responses = [
            makeResponse(round: 1, responder: a, value: a.uuidString),
            makeResponse(round: 1, responder: b, value: a.uuidString), // match
            makeResponse(round: 2, responder: a, value: a.uuidString),
            makeResponse(round: 2, responder: b, value: b.uuidString), // no match
            makeResponse(round: 3, responder: a, value: "option_a"),
            // round 3: partner hasn't answered — shouldn't count either way
        ]
        #expect(GameLogic.matchCount(rounds: rounds, responses: responses, partnerAID: a, partnerBID: b) == 1)
    }

    @Test func matchPercentageRoundsToNearestWholeNumber() {
        #expect(GameLogic.matchPercentage(matches: 2, totalRounds: 5) == 40)
        #expect(GameLogic.matchPercentage(matches: 1, totalRounds: 3) == 33)
        #expect(GameLogic.matchPercentage(matches: 0, totalRounds: 0) == 0)
    }

    @Test func matchedRoundsExcludesMutualSkips() {
        let session = UUID()
        let a = UUID()
        let b = UUID()
        let rounds = [makeRound(session: session, number: 1), makeRound(session: session, number: 2)]
        let responses = [
            makeResponse(round: 1, responder: a, value: "Japan"),
            makeResponse(round: 1, responder: b, value: "Japan"), // real match
            makeResponse(round: 2, responder: a, value: ""),
            makeResponse(round: 2, responder: b, value: ""), // mutual skip — not a "biggest match"
        ]
        let matched = GameLogic.matchedRounds(rounds: rounds, responses: responses, partnerAID: a, partnerBID: b)
        #expect(matched.map(\.roundNumber) == [1])
    }

    @Test func mismatchedRoundsAreFramedForDiscussion() {
        let session = UUID()
        let a = UUID()
        let b = UUID()
        let rounds = [makeRound(session: session, number: 1)]
        let responses = [
            makeResponse(round: 1, responder: a, value: "Me"),
            makeResponse(round: 1, responder: b, value: "Himself"),
        ]
        let mismatched = GameLogic.mismatchedRounds(rounds: rounds, responses: responses, partnerAID: a, partnerBID: b)
        #expect(mismatched.map(\.roundNumber) == [1])
    }

    // MARK: - Discuss Before Travelling completion

    @Test func discussionNotCompleteUntilEveryRoundIsMarked() {
        let rounds = [
            makeRound(number: 1, discussionStatus: .talkedAbout),
            makeRound(number: 2, discussionStatus: nil),
        ]
        #expect(GameLogic.discussionComplete(rounds: rounds) == false)
    }

    @Test func discussionCompleteWhenAllRoundsMarkedEitherWay() {
        let rounds = [
            makeRound(number: 1, discussionStatus: .talkedAbout),
            makeRound(number: 2, discussionStatus: .comeBackLater),
        ]
        #expect(GameLogic.discussionComplete(rounds: rounds) == true)
    }

    @Test func discussionNotCompleteWhenThereAreNoRounds() {
        #expect(GameLogic.discussionComplete(rounds: []) == false)
    }

    // MARK: - Completed history filtering

    @Test func completedSessionsOnlyExcludesActiveAndAbandoned() {
        func session(status: GameSessionStatus) -> GameSession {
            GameSession(id: UUID(), coupleID: UUID(), gameType: .travelTrivia, initiatorID: UUID(), status: status, totalRounds: 5, isDaily: false, deckID: nil, startedAt: nil, completedAt: nil, createdAt: .now, updatedAt: .now)
        }
        let sessions = [session(status: .active), session(status: .completed), session(status: .abandoned), session(status: .waitingForPartner)]
        let completed = GameLogic.completedSessionsOnly(sessions)
        #expect(completed.count == 1)
        #expect(completed.first?.status == .completed)
    }

    // MARK: - Game metadata / Globe homepage card wiring

    @Test func fourGamesAreRecommendedOnTheHomeHomepage() {
        #expect(Set(RecommendedGamesSection.recommended) == Set(GameType.allCases))
        #expect(RecommendedGamesSection.recommended.count == 4)
    }

    @Test func eachGameHasTheSpecifiedTypeLabelAndDuration() {
        #expect(GameType.travelTrivia.category == .compete)
        #expect(GameType.travelTrivia.durationMinutes == 12)
        #expect(GameType.moreLikely.category == .compete)
        #expect(GameType.moreLikely.durationMinutes == 8)
        #expect(GameType.thisOrThat.category == .connect)
        #expect(GameType.thisOrThat.durationMinutes == 6)
        #expect(GameType.discussBeforeTravelling.category == .connect)
        #expect(GameType.discussBeforeTravelling.durationMinutes == 15)
    }

    @Test func everyGameTypeHasAUniqueDisplayName() {
        let names = Set(GameType.allCases.map(\.displayName))
        #expect(names.count == GameType.allCases.count)
    }
}
