//
//  GameTypeDecksView.swift
//  Twofold
//
//  Tapping a game type card (Compete/Connect section) opens this instead of jumping straight
//  into a random session — every deck of that type, across every topic, with in-progress ones
//  surfaced first. Decks are the real playable unit now (see TopicsSection), so this is the
//  game-type-scoped equivalent of TopicDetailView's topic-scoped deck list.
//

import PostHog
import SwiftUI

struct GameTypeDecksView: View {
    let gameType: GameType

    @Environment(AppModel.self) private var appModel

    private var allDecks: [GameDeck] {
        appModel.decks(ofType: gameType)
    }

    private var unansweredDecks: [GameDeck] {
        allDecks
            .filter { !(appModel.deckProgress?[$0.id]?.bothCompleted ?? false) }
            .sorted { lhs, rhs in
                // Started means answered, not merely opened — see `DeckProgress.hasAnyAnswers`.
                let lhsStarted = appModel.deckProgress?[lhs.id]?.hasAnyAnswers ?? false
                let rhsStarted = appModel.deckProgress?[rhs.id]?.hasAnyAnswers ?? false
                if lhsStarted != rhsStarted { return lhsStarted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    /// Most recently completed first — see `GameLogic.completedDeckPrecedes`. The curated
    /// `sortOrder` these used to be listed in is meaningless once a deck is finished, and read as
    /// random next to the "Completed <date>" each card shows.
    private var answeredDecks: [GameDeck] {
        allDecks
            .filter { appModel.deckProgress?[$0.id]?.bothCompleted ?? false }
            .sorted { GameLogic.completedDeckPrecedes($0, $1, progress: appModel.deckProgress) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text(gameType.tagline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.sm)

                deckSection(title: "Unanswered", decks: unansweredDecks)
                deckSection(title: "Answered", decks: answeredDecks)

                if allDecks.isEmpty {
                    Text("No decks yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await appModel.loadGameDecksIfNeeded() }
        .postHogScreenView("Games: Type Decks")
    }

    @ViewBuilder
    private func deckSection(title: String, decks: [GameDeck]) -> some View {
        if !decks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(decks) { deck in
                        DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id], showsTopicPill: true)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GameTypeDecksView(gameType: .triviaBattle)
    }
    .environment(AppModel())
}
