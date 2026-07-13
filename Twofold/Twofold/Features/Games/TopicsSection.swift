//
//  TopicsSection.swift
//  Twofold
//
//  Browsable/informational only, deliberately not a second way to start a session — tapping a
//  topic opens a detail sheet (which games include it + how much you've played), but actually
//  playing still goes through the 4 GameType cards above. Progress bars are computed client-side
//  in AppModel (loadGameContentCatalogIfNeeded/topicProgress) from the couple's own play
//  history, not a dedicated RPC.
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
        .task { await appModel.loadGameContentCatalogIfNeeded() }
        .sheet(item: $selectedTopic) { topic in
            TopicDetailView(topic: topic)
        }
    }

    private func topicRow(_ topic: GameTopic) -> some View {
        let progress = appModel.topicProgress(topic)
        return HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(topic.color.opacity(0.18))
                Image(systemName: topic.icon).foregroundStyle(topic.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                ProgressView(value: Double(progress?.played ?? 0), total: Double(max(progress?.total ?? 1, 1)))
                    .tint(topic.color)
                if let progress, progress.total > 0 {
                    Text("\(progress.played)/\(progress.total) played")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }
            }

            Spacer()
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
                VStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle().fill(topic.color.opacity(0.18))
                        Image(systemName: topic.icon).font(.largeTitle).foregroundStyle(topic.color)
                    }
                    .frame(width: 72, height: 72)

                    if let progress = appModel.topicProgress(topic), progress.total > 0 {
                        Text("\(progress.played) of \(progress.total) played")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(appModel.gameTypes(for: topic), id: \.gameType) { entry in
                            HStack {
                                Image(systemName: entry.gameType.icon).foregroundStyle(topic.color)
                                Text(entry.gameType.displayName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(entry.count)").font(.caption).foregroundStyle(Theme.subtleInk)
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                    }

                    Text("Play any of these games to explore \(topic.displayName.lowercased()) — topics are mixed together within each game, so there's no way to jump straight into just one.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
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
