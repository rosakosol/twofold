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

    /// Split out of `body` deliberately: adding the offline branch below pushed the whole
    /// HomeView expression tree past what the Swift type checker would solve in reasonable time
    /// ("unable to type-check this expression in reasonable time" at HomeView's own call site).
    /// Isolating it here keeps each builder small enough to infer.
    @ViewBuilder
    private var deckContent: some View {
        if appModel.gameDecks == nil, appModel.gameDecksUnavailable {
            // Decks are fetched, never bundled, and the fetch swallows its error — so this used
            // to sit on the spinner below forever whenever it failed, reading as a hang rather
            // than a limitation. `loadGameDecksIfNeeded` leaves `gameDecks` nil on failure, so it
            // re-attempts on the next appearance and this resolves itself once it can load.
            Text("Game packs need a connection — they'll load when you're back online.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Spacing.sm)
        } else if appModel.gameDecks == nil {
            // Hasn't resolved yet — sized to roughly match a real `DeckCardRow` so the swap-in
            // doesn't visibly jump.
            ProgressView()
                .frame(height: 150)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(randomDecks) { deck in
                        DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id], showsTopic: true)
                            .frame(width: 220)
                    }
                }
                .padding(.vertical, 2)
            }
        }
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

            deckContent
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
