//
//  GamesHubView.swift
//  Twofold
//
//  Reachable both as the Games tab's root and as a sheet from the Globe homepage's
//  "See all games". Organizes the 4 games into Compete / Connect / Travel — "Travel" is a
//  second, cross-cutting grouping (every current game is travel-themed), not mutually
//  exclusive with the Compete/Connect type badge shown on each card.
//

import SwiftUI

struct GamesHubView: View {
    @Environment(AppModel.self) private var appModel

    private var competeGames: [GameType] { GameType.allCases.filter { $0.category == .compete } }
    private var connectGames: [GameType] { GameType.allCases.filter { $0.category == .connect } }
    private var travelGames: [GameType] { GameType.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    section(title: "Compete", games: competeGames)
                    section(title: "Connect", games: connectGames)
                    section(title: "Travel", games: travelGames)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GameHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
    }

    private func section(title: String, games: [GameType]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(games) { gameType in
                    if appModel.partnerConnected {
                        NavigationLink {
                            GameEntryView(gameType: gameType)
                        } label: {
                            GameCard(gameType: gameType)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GameCard(gameType: gameType, isLocked: true)
                    }
                }
            }
        }
    }
}

#Preview {
    GamesHubView()
        .environment(AppModel())
}
