//
//  GameDestinationView.swift
//  Twofold
//
//  The one place that maps a session's `GameType` to its typed game view — reused everywhere a
//  session needs to be opened by id alone (game history, deck cards' "view results"/"reset",
//  push notification deep links), instead of duplicating this switch at every call site.
//

import SwiftUI

struct SessionRoute: Identifiable, Hashable {
    let id: UUID
    let gameType: GameType
}

/// `title` overrides the generic game-type nav title (e.g. with a deck's own title) — passed
/// through so the title doesn't shift from "Airport Chaos" to "Trivia Battle" the moment play
/// actually starts, which is exactly what happened when each typed view set its own title
/// independently of whatever title the caller had already shown.
///
/// `topic` is the deck's raw `GameTopic` string (nil for a non-deck/shared-pool session, which
/// has no topic) — only Trivia Battle and Deep Conversation currently show it as a badge on the
/// play screen itself, matching the same badge already shown on the deck's own card.
@ViewBuilder
func gameDestinationView(gameType: GameType, sessionID: UUID, title: String? = nil, topic: String? = nil) -> some View {
    switch gameType {
    case .triviaBattle: TriviaBattleGameView(sessionID: sessionID, title: title, topic: topic)
    case .moreLikely: WhosMoreLikelyGameView(sessionID: sessionID, title: title)
    case .thisOrThat: ThisOrThatGameView(sessionID: sessionID, title: title)
    case .deepConversations: DeepConversationsGameView(sessionID: sessionID, title: title, topic: topic)
    }
}
