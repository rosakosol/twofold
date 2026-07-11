//
//  RecommendedGamesSection.swift
//  Twofold
//
//  Globe homepage section. Game metadata (title/tagline/duration/icon) is static local content
//  (see `GameType`), not a network fetch, so there's no loading/error state to handle here —
//  only actual game sessions are server-driven, and those live behind `GameEntryView`.
//

import SwiftUI

struct RecommendedGamesSection: View {
    static let recommended: [GameType] = [.travelTrivia, .moreLikely, .thisOrThat, .discussBeforeTravelling]

    /// `GamesHubView` wraps itself in its own `NavigationStack` (it doubles as the Games tab's
    /// root), so it's presented as a sheet here rather than pushed — pushing a
    /// NavigationStack-wrapped view onto another NavigationStack via NavigationLink produces
    /// nested/doubled navigation chrome.
    @State private var showingHub = false

    var body: some View {
        SectionCard {
            HStack {
                Text("Recommended games")
                    .font(.headline)
                Spacer()
                Button {
                    showingHub = true
                } label: {
                    Text("See all games")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.skyBlue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.recommended) { gameType in
                        NavigationLink {
                            GameEntryView(gameType: gameType)
                        } label: {
                            GameCard(gameType: gameType, width: 220)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .sheet(isPresented: $showingHub) {
            GamesHubView()
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
