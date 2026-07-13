//
//  GameTypeDecksView.swift
//  Twofold
//
//  Tapping a game type card (Compete/Connect/Travel section) opens this instead of jumping
//  straight into a random session — every deck of that type, across every topic, with
//  in-progress ones surfaced first. Decks are the real playable unit now (see TopicsSection),
//  so this is the game-type-scoped equivalent of TopicDetailView's topic-scoped deck list.
//

import SwiftUI

struct GameTypeDecksView: View {
    let gameType: GameType
    /// Set when opened from the Games hub's "Travel" section — that section is a cross-cutting
    /// grouping distinct from a topic, so tapping a game type card there should only surface
    /// decks actually tagged Travel, not every deck of that type across every topic (which is
    /// what tapping the same card under Compete/Connect still does).
    var topicFilter: GameTopic? = nil

    @Environment(AppModel.self) private var appModel

    private var allDecks: [GameDeck] {
        let decks = appModel.decks(ofType: gameType)
        guard let topicFilter else { return decks }
        return decks.filter { $0.topic == topicFilter.rawValue }
    }

    private var unansweredDecks: [GameDeck] {
        allDecks
            .filter { !(appModel.deckProgress?[$0.id]?.bothCompleted ?? false) }
            .sorted { lhs, rhs in
                let lhsStarted = appModel.deckProgress?[lhs.id] != nil
                let rhsStarted = appModel.deckProgress?[rhs.id] != nil
                if lhsStarted != rhsStarted { return lhsStarted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var answeredDecks: [GameDeck] {
        allDecks
            .filter { appModel.deckProgress?[$0.id]?.bothCompleted ?? false }
            .sorted { $0.sortOrder < $1.sortOrder }
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
                    Text(topicFilter != nil ? "No travel decks yet." : "No decks yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(topicFilter != nil ? "Travel \(gameType.displayName)" : gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await appModel.loadGameDecksIfNeeded() }
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
        GameTypeDecksView(gameType: .travelTrivia)
    }
    .environment(AppModel())
}
