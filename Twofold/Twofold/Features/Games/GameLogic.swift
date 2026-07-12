//
//  GameLogic.swift
//  Twofold
//
//  Pure decision logic shared by every game's view + `GameSessionStore` — kept free of
//  SwiftUI/networking so it's directly unit-testable (see TwofoldTests/GameLogicTests.swift).
//

import Foundation

enum GameLogic {
    /// Distinct rounds a given responder has answered — the basis for independent per-partner
    /// pacing (each partner just walks through their own unanswered rounds, no per-round
    /// waiting on the other person).
    static func answeredRoundNumbers(responses: [GameResponse], responderID: UUID) -> Set<Int> {
        Set(responses.filter { $0.responderID == responderID }.map(\.roundNumber))
    }

    /// Where a specific partner is in the session, for the completion screen's status stepper.
    static func partnerProgress(responses: [GameResponse], partnerID: UUID, totalRounds: Int) -> PartnerProgress {
        let answered = answeredRoundNumbers(responses: responses, responderID: partnerID).count
        if answered == 0 { return .notStarted }
        if answered >= totalRounds { return .finished }
        return .inProgress(answered: answered, total: totalRounds)
    }

    /// Number of correct answers a given responder has logged for a trivia session.
    static func triviaScore(responses: [GameResponse], responderID: UUID) -> Int {
        responses.filter { $0.responderID == responderID && $0.isCorrect == true }.count
    }

    enum TriviaOutcome: Hashable {
        case winner(UUID)
        case tie
    }

    static func triviaOutcome(responses: [GameResponse], partnerAID: UUID, partnerBID: UUID) -> TriviaOutcome {
        let scoreA = triviaScore(responses: responses, responderID: partnerAID)
        let scoreB = triviaScore(responses: responses, responderID: partnerBID)
        if scoreA == scoreB { return .tie }
        return scoreA > scoreB ? .winner(partnerAID) : .winner(partnerBID)
    }

    /// Rounds where both partners have answered and their answer values match — the shared
    /// basis for both Who's More Likely To and This or That's "match" concept.
    static func matchCount(rounds: [GameSessionRound], responses: [GameResponse], partnerAID: UUID, partnerBID: UUID) -> Int {
        rounds.filter { round in
            guard let a = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerAID }),
                  let b = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerBID }) else {
                return false
            }
            return a.answerValue == b.answerValue
        }.count
    }

    static func matchPercentage(matches: Int, totalRounds: Int) -> Int {
        guard totalRounds > 0 else { return 0 }
        return Int((Double(matches) / Double(totalRounds) * 100).rounded())
    }

    /// Rounds both partners answered the same (excluding mutual skips) — the results screen's
    /// "Biggest Match" pool, in round order.
    static func matchedRounds(rounds: [GameSessionRound], responses: [GameResponse], partnerAID: UUID, partnerBID: UUID) -> [GameSessionRound] {
        rounds.filter { round in
            guard let a = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerAID }),
                  let b = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerBID }),
                  !a.answerValue.isEmpty else { return false }
            return a.answerValue == b.answerValue
        }
    }

    /// Rounds where both partners answered but chose differently — reframed on the results
    /// screen as "Questions to discuss" rather than "you disagreed."
    static func mismatchedRounds(rounds: [GameSessionRound], responses: [GameResponse], partnerAID: UUID, partnerBID: UUID) -> [GameSessionRound] {
        rounds.filter { round in
            guard let a = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerAID }),
                  let b = responses.first(where: { $0.roundNumber == round.roundNumber && $0.responderID == partnerBID }) else { return false }
            return a.answerValue != b.answerValue
        }
    }

    /// A discuss-type session is done once every round has been marked "talked about" or
    /// "come back later" — no scores or winners involved.
    static func discussionComplete(rounds: [GameSessionRound]) -> Bool {
        !rounds.isEmpty && rounds.allSatisfy { $0.discussionStatus != nil }
    }

    static func completedSessionsOnly(_ sessions: [GameSession]) -> [GameSession] {
        sessions.filter { $0.status == .completed }
    }
}
