//
//  TopicsSection.swift
//  Twofold
//
//  Tapping a topic opens a detail sheet listing that topic's curated decks — real, individually
//  playable mini-games (see `GameDeck`), not just a filtered view over the shared pools. Progress
//  bars reflect how many of a topic's decks the couple has started, computed client-side in
//  AppModel from the couple's own play history (no dedicated RPC).
//

import PostHog
import SwiftUI

struct TopicsSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTopic: GameTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Topics")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(GameTopic.allCases) { topic in
                    Button {
                        selectedTopic = topic
                    } label: {
                        topicRow(topic)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await appModel.loadGameDecksIfNeeded() }
        .sheet(item: $selectedTopic) { topic in
            TopicDetailView(topic: topic)
        }
    }

    private func topicRow(_ topic: GameTopic) -> some View {
        let progress = appModel.topicProgress(topic)
        let fraction = progress.map { $0.total > 0 ? Double($0.played) / Double($0.total) : 0 } ?? 0
        let percent = Int((fraction * 100).rounded())

        return HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(topic.color.opacity(0.18))
                Image(systemName: topic.icon).foregroundStyle(topic.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                ProgressView(value: fraction)
                    .tint(topic.color)
            }

            if progress != nil {
                Text("\(percent)%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct TopicDetailView: View {
    let topic: GameTopic

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// In-progress decks first, then never-started ones — completed decks are shown separately.
    private var unansweredDecks: [GameDeck] {
        appModel.decks(for: topic)
            .filter { !(appModel.deckProgress?[$0.id]?.bothCompleted ?? false) }
            .sorted { lhs, rhs in
                let lhsStarted = appModel.deckProgress?[lhs.id] != nil
                let rhsStarted = appModel.deckProgress?[rhs.id] != nil
                if lhsStarted != rhsStarted { return lhsStarted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var answeredDecks: [GameDeck] {
        appModel.decks(for: topic)
            .filter { appModel.deckProgress?[$0.id]?.bothCompleted ?? false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle().fill(topic.color.opacity(0.18))
                        Image(systemName: topic.icon).font(.largeTitle).foregroundStyle(topic.color)
                    }
                    .frame(width: 72, height: 72)
                    .padding(.top, Theme.Spacing.sm)

                    deckSection(title: "Unanswered", decks: unansweredDecks)
                    deckSection(title: "Answered", decks: answeredDecks)

                    if appModel.decks(for: topic).isEmpty {
                        Text("No decks in this topic yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .padding(.top, Theme.Spacing.lg)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(topic.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .postHogScreenView("Games: Topic Detail")
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
                        DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id])
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            TopicsSection()
                .padding()
        }
        .background(Theme.backgroundGradient)
    }
    .environment(AppModel())
}
