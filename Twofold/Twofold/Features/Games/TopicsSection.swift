//
//  TopicsSection.swift
//  Twofold
//
//  Tapping a topic opens a detail sheet listing that topic's curated decks — real, individually
//  playable mini-games (see `GameDeck`), not just a filtered view over the shared pools. Progress
//  bars reflect how many of a topic's decks the couple has started, computed client-side in
//  AppModel from the couple's own play history (no dedicated RPC).
//

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(topic.color.opacity(0.18))
                        Image(systemName: topic.icon).font(.largeTitle).foregroundStyle(topic.color)
                    }
                    .frame(width: 72, height: 72)
                    .padding(.top, Theme.Spacing.sm)

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(appModel.decks(for: topic)) { deck in
                            deckCard(deck)
                        }
                    }

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
    }

    @ViewBuilder
    private func deckCard(_ deck: GameDeck) -> some View {
        let isLocked = deck.tier == "premium" && appModel.subscriptionTier != "premium"
        if isLocked {
            deckCardContent(deck, isLocked: true)
        } else if appModel.partnerConnected {
            NavigationLink {
                DeckEntryView(deck: deck)
            } label: {
                deckCardContent(deck, isLocked: false)
            }
            .buttonStyle(.plain)
        } else {
            deckCardContent(deck, isLocked: true)
        }
    }

    private func deckCardContent(_ deck: GameDeck, isLocked: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: deck.gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(deck.emoji).font(.title2)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                PillBadge(text: deck.gameType.shortLabel, tint: deck.gameType.iconGradient.first ?? Theme.skyBlue)
                Text(deck.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if isLocked {
                ZStack {
                    Circle().fill(Theme.subtleInk.opacity(0.12))
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                .frame(width: 30, height: 30)
            } else {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.subtleInk.opacity(0.12), lineWidth: 1)
        }
        .opacity(isLocked ? 0.7 : 1)
        .contentShape(Rectangle())
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
