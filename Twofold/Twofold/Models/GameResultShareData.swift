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

/// One topic + both answers from a multi-round Deep Conversations deck — lets the share sheet
/// offer a "choose a topic to feature" picker. Deep Conversations answers are free text with no
/// right answer to compare against (unlike This-or-That/More-Likely's `matchPercent`), so this is
/// deliberately about picking *which* exchange to show off, never whether the two of you "matched."
struct GameResultShareRound: Identifiable {
    let id = UUID()
    let question: String
    let myAnswer: String
    let partnerAnswer: String
}

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
    /// Every topic from a multi-round Deep Conversations deck (not the Daily Question, which has
    /// exactly one round already covered by `singleRoundQuestion` below, so this stays nil for
    /// it). nil for every other game type.
    let deepConversationRounds: [GameResultShareRound]?

    // MARK: Single-round layouts (daily streak / names & answer / speech bubble)

    /// The question+both-answers currently featured on the `.namesAndAnswer`/`.speechBubble`
    /// layouts. Set once from the Daily Question's own (and only) round; for a multi-round Deep
    /// Conversations deck these start nil and `GameResultsShareView` overwrites them from
    /// whichever entry in `deepConversationRounds` the person picks — `var`, not `let`, for
    /// exactly that reason.
    var singleRoundQuestion: String?
    var myAnswer: String?
    var partnerAnswer: String?
    let dailyStreak: Int?

    /// The Daily Question has no score/match stat to headline — `scoreSnapshot` would render as
    /// just a brand mark and avatars — so it's skipped there in favor of the two single-Q&A
    /// layouts. Deep Conversations decks have no match/score concept either (free text, nothing
    /// to compare), so they skip `scoreSnapshot` too and go straight to the two single-Q&A
    /// layouts once a topic's been picked (see `GameResultsShareView.selectedRoundIndex`). Every
    /// other game type gets `scoreSnapshot`.
    var availableLayouts: [GameResultShareLayout] {
        if isDaily {
            var layouts: [GameResultShareLayout] = []
            if dailyStreak != nil, singleRoundQuestion != nil {
                layouts.append(.dailyStreak)
            }
            if singleRoundQuestion != nil {
                layouts.append(.namesAndAnswer)
                layouts.append(.speechBubble)
            }
            return layouts
        }
        if gameType == .deepConversations {
            guard deepConversationRounds?.isEmpty == false else { return [] }
            return [.namesAndAnswer, .speechBubble]
        }
        return [.scoreSnapshot]
    }
}
