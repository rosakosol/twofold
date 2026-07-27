//
//  RecommendedGamesSection.swift
//  Twofold
//
//  Globe homepage section — a random taste of real, playable decks (not the abstract game-type
//  cards `GamesHubView`'s own row shows), so tapping through lands on actual content immediately.
//  "See all games" switches to the real Games tab (`onSeeAllGames`, wired by `MainTabView`) rather
//  than opening a sheet copy of it, so back/tab-bar navigation behaves exactly like any other tab.
//

import SwiftUI

struct RecommendedGamesSection: View {
    @Environment(AppModel.self) private var appModel
    /// Set by `MainTabView` to flip its own tab selection to Games — defaults to a no-op so the
    /// preview below (and any future caller that doesn't care) still compiles.
    var onSeeAllGames: () -> Void = {}

    /// Chosen once (see `.task` below), not recomputed on every render — a plain `.shuffled()`
    /// computed property would reshuffle on any unrelated state change elsewhere in `AppModel`,
    /// visibly reordering cards a user might be mid-scroll through.
    @State private var randomDeckIDs: [GameDeck.ID] = []

    private var randomDecks: [GameDeck] {
        guard let decks = appModel.gameDecks else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0) })
        return randomDeckIDs.compactMap { byID[$0] }
    }

    var body: some View {
        SectionCard {
            HStack {
                Text("Recommended games")
                    .font(.headline)
                Spacer()
                Button(action: onSeeAllGames) {
                    Text("See all games")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.skyBlue)
                }
            }

            if appModel.gameDecks == nil {
                // `loadGameDecksIfNeeded()` (below) hasn't resolved yet — sized to roughly match
                // a real `DeckCardRow` so the swap-in doesn't visibly jump.
                ProgressView()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(randomDecks) { deck in
                            DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id], showsTopicPill: true)
                                .frame(width: 220)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            await appModel.loadGameDecksIfNeeded()
            guard randomDeckIDs.isEmpty, let decks = appModel.gameDecks, !decks.isEmpty else { return }
            // Same "still worth showing" filter `GamesHubView`'s own Travel carousel uses —
            // a deck both partners already finished isn't a useful "recommendation."
            let unfinished = decks.filter { appModel.deckProgress?[$0.id]?.bothCompleted != true }
            randomDeckIDs = Array(unfinished.shuffled().prefix(5)).map(\.id)
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            RecommendedGamesSection()
                .padding()
        }
        .background(Theme.backgroundGradient)
    }
    .environment(AppModel())
}
