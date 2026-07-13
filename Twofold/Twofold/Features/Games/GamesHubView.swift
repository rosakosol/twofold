//
//  GamesHubView.swift
//  Twofold
//
//  Reachable both as the Games tab's root and as a sheet from the Globe homepage's
//  "See all games". Organizes the 4 games into Compete / Connect / Travel — "Travel" is a
//  second, cross-cutting grouping (every current game is travel-themed), not mutually
//  exclusive with the Compete/Connect type badge shown on each card. Tapping a game type card
//  opens `GameTypeDecksView` (every deck of that type, across every topic) rather than jumping
//  straight into a random session — decks are the real playable unit now, see TopicsSection.
//

import SwiftUI

/// `.navigationDestination(item:)` needs an `Identifiable` value — this wraps an optional filter
/// so both "no filter, just search" (search icon) and a specific pill both resolve to a value.
private struct BrowseRoute: Identifiable, Hashable {
    let filter: DeckBrowseFilter?
    var id: String { filter?.rawValue ?? "all" }
}

struct GamesHubView: View {
    @Environment(AppModel.self) private var appModel
    @State private var browseRoute: BrowseRoute?
    /// Tapping a locked (partner-required) card opens this rather than doing nothing — a lock
    /// badge with no tap action just teaches people the card is broken.
    @State private var showingPartnerSetup = false

    private var competeGames: [GameType] { GameType.allCases.filter { $0.category == .compete } }
    private var connectGames: [GameType] { GameType.allCases.filter { $0.category == .connect } }
    private var travelGames: [GameType] { GameType.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if appModel.partnerConnected {
                        searchAndFilterBar
                        DailyActivityCard()
                    }
                    section(title: "Compete", games: competeGames)
                    section(title: "Connect", games: connectGames)
                    section(title: "Travel", games: travelGames, topicFilter: .travel)
                    if appModel.partnerConnected {
                        TopicsSection()
                    }
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
            .navigationDestination(item: $browseRoute) { route in
                AllDecksBrowseView(initialFilter: route.filter)
            }
            .sheet(isPresented: $showingPartnerSetup) {
                PartnerSetupView()
            }
        }
    }

    private var searchAndFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    browseRoute = BrowseRoute(filter: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.cardBackground, in: Circle())
                }
                .buttonStyle(.plain)

                ForEach(DeckBrowseFilter.allCases) { filter in
                    Button {
                        browseRoute = BrowseRoute(filter: filter)
                    } label: {
                        Label(filter.rawValue, systemImage: filter.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .foregroundStyle(Theme.ink)
                            .background(Theme.cardBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func section(title: String, games: [GameType], topicFilter: GameTopic? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(games) { gameType in
                        if appModel.partnerConnected {
                            NavigationLink {
                                GameTypeDecksView(gameType: gameType, topicFilter: topicFilter)
                            } label: {
                                GameCard(gameType: gameType, width: 220)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                showingPartnerSetup = true
                            } label: {
                                GameCard(gameType: gameType, width: 220, isLocked: true)
                            }
                            .buttonStyle(.plain)
                        }
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
