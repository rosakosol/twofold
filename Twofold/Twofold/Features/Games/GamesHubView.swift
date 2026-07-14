//
//  GamesHubView.swift
//  Twofold
//
//  Reachable both as the Games tab's root and as a sheet from the Globe homepage's
//  "See all games". Travel leads (it's the app's namesake topic) and shows its own real curated
//  decks directly — not the generic game-type cards Compete/Connect use — so someone lands on
//  actual playable content, not another layer of picking a mechanic first. Compete/Connect below
//  it group the 4 game types by category; tapping one opens `GameTypeDecksView` (every deck of
//  that type, across every topic) rather than jumping straight into a random session — decks are
//  the real playable unit now, see TopicsSection.
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
    private var travelDecks: [GameDeck] { appModel.decks(for: .travel) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if appModel.partnerConnected {
                        searchAndFilterBar
                        DailyActivityCard()
                    }
                    travelSection
                    section(title: "Compete", games: competeGames)
                    section(title: "Connect", games: connectGames)
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

    private func section(title: String, games: [GameType]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(games) { gameType in
                        if appModel.partnerConnected {
                            NavigationLink {
                                GameTypeDecksView(gameType: gameType)
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

    /// The Travel topic's own curated decks, shown directly (not the generic game-type cards the
    /// sections below use) — Travel is the app's namesake, so it gets real playable content up
    /// front rather than one more layer of picking a mechanic.
    private var travelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Travel")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(travelDecks) { deck in
                        DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id])
                            .frame(width: 260)
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
