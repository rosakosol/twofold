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

@ViewBuilder
func gameDestinationView(gameType: GameType, sessionID: UUID) -> some View {
    switch gameType {
    case .travelTrivia: TravelTriviaGameView(sessionID: sessionID)
    case .moreLikely: WhosMoreLikelyGameView(sessionID: sessionID)
    case .thisOrThat: ThisOrThatGameView(sessionID: sessionID)
    case .discussBeforeTravelling: DiscussBeforeTravellingGameView(sessionID: sessionID)
    }
}
