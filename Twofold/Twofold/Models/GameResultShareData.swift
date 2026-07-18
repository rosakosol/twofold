//
//  GameResultShareData.swift
//  Twofold
//
//  Plain snapshot of everything a share card needs — built once by `GameResultsView` from its
//  own already-computed state, so the card views themselves stay pure and don't reach back into
//  a live `GameSessionStore`. Same reasoning as `RelationshipStatsShareCard` taking plain
//  `Couple`/`Trip`/`Memory` values rather than a store.
//

import Foundation

struct GameResultShareData {
    let gameType: GameType
    let title: String
    let isDaily: Bool
    let me: Person
    let partner: Person

    // MARK: Score snapshot layout

    /// 0...100 — thisOrThat / moreLikely only.
    let matchPercent: Int?
    let triviaMyScore: Int?
    let triviaPartnerScore: Int?
    let triviaTotalRounds: Int?
    /// "Talked about X of Y topics" — deepConversations only, and only when it isn't the single-
    /// round Daily Question (which uses the single-round fields below instead).
    let deepConversationSummary: String?

    // MARK: Single-round layouts (daily streak / names & answer)

    /// Set only when the session has exactly one round — in practice, the Daily Question.
    let singleRoundQuestion: String?
    let myAnswer: String?
    let partnerAnswer: String?
    let dailyStreak: Int?

    /// The Daily Question has no score/match/summary stat to headline — `scoreSnapshot` would
    /// render as just a brand mark and avatars — so it's skipped there in favor of the two
    /// single-Q&A layouts. Every other game type only ever gets `scoreSnapshot`, since they're
    /// multi-round and have no single Q&A to headline instead.
    var availableLayouts: [GameResultShareLayout] {
        guard isDaily else { return [.scoreSnapshot] }
        var layouts: [GameResultShareLayout] = []
        if dailyStreak != nil, singleRoundQuestion != nil {
            layouts.append(.dailyStreak)
        }
        if singleRoundQuestion != nil {
            layouts.append(.namesAndAnswer)
        }
        return layouts
    }
}
