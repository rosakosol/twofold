//
//  GamesHubView.swift
//  Twofold
//
//  Reachable both as the Games tab's root and via "See all games" from the Globe homepage. Game
//  types (one swipeable row, no more Compete/Connect split) lead, then Travel — the app's
//  namesake topic — shows its own real curated decks directly. Tapping a game type opens
//  `GameTypeDecksView` (every deck of that type, across every topic) rather than jumping straight
//  into a random session — decks are the real playable unit now, see TopicsSection.
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var browseRoute: BrowseRoute?
    /// Tapping a locked (partner-required) card opens this rather than doing nothing — a lock
    /// badge with no tap action just teaches people the card is broken. Goes straight to
    /// `PartnerRequiredGateView`'s share/redeem code UI, not the full `PartnerSetupView` profile
    /// editor — the user's already told us they want to unlock something, not edit a profile.
    @State private var showingPartnerGate = false
    /// Unfinished puzzles and boards, for the section at the top. Loaded every time the tab
    /// appears rather than once: coming back here after playing is exactly when it has changed.
    @State private var openGames: [BackendService.OpenGame] = []

    /// Once both partners have finished a Travel deck it drops off this carousel — Travel is
    /// the app's front-door showcase, so it stays focused on what's still playable rather than
    /// accumulating finished decks the way the full topic/browse lists intentionally do (those
    /// keep completed decks visible, since jumping straight to results from a finished deck is
    /// still a useful shortcut there).
    private var travelDecks: [GameDeck] {
        appModel.decks(for: .travel).filter { appModel.deckProgress?[$0.id]?.bothCompleted != true }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    searchAndFilterBar
                    DailyActivityCard()
                    // Above everything else, because it is the only part of this screen that is
                    // about something already underway — and on a tab you open to find out whether
                    // your partner has moved, that is the answer you came for.
                    OpenGamesSection(games: openGames, partnerName: appModel.partner.name)
                    conversationGamesSection
                    puzzlesSection
                    travelSection
                    TopicsSection()
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        browseRoute = BrowseRoute(filter: nil)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Browse all decks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GameHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Game history")
                }
            }
            .navigationDestination(item: $browseRoute) { route in
                AllDecksBrowseView(initialFilter: route.filter)
            }
            .sheet(isPresented: $showingPartnerGate) {
                PartnerRequiredGateView()
            }
            .task { await appModel.loadGameDecksIfNeeded() }
            .task { openGames = await BackendService.fetchOpenGames() }
            .refreshable {
                await appModel.refreshAll()
                openGames = await BackendService.fetchOpenGames()
            }
        }
    }

    /// Plain (non-scrolling) row, each pill given equal width — search moved out to its own
    /// leading toolbar button (in line with the "past games" one), which freed up enough room
    /// for all 3 filter pills to fit on one row without needing horizontal scroll.
    ///
    /// Three-across only holds while each label still fits its third of the row. At accessibility
    /// text sizes it doesn't: "Your turn" wrapped to *one letter per line* and the three capsules
    /// grew tall enough to fill the entire screen, burying the daily question and every game below
    /// them — the Games tab was unreachable. So the row becomes one full-width pill per line there,
    /// where the labels have room to stay on a single line. `lineLimit(1)` + `minimumScaleFactor`
    /// covers the large-but-not-accessibility sizes in between, which still use three-across.
    private var searchAndFilterBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        return layout {
            ForEach(DeckBrowseFilter.allCases) { filter in
                Button {
                    browseRoute = BrowseRoute(filter: filter)
                } label: {
                    Label(filter.rawValue, systemImage: filter.icon)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        // Only shrink while three pills share a row. Stacked full-width at
                        // accessibility sizes there is nothing to shrink for, and scaling the
                        // label back down would undo the setting the reader just asked for.
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.cardBackground, in: Capsule())
                        // A plain flat fill left these three pills with no edge of their own at
                        // all in dark mode, reading as one undifferentiated bar rather than three
                        // distinct filters. Neutral hairline (not a colored gradient — these pills
                        // don't represent a blue/green/red state, just a filter choice, and Aurora
                        // rule #2 keeps color meaningful rather than decorative). Light mode
                        // already reads fine against its own pale background without a border.
                        .overlay {
                            if colorScheme == .dark {
                                Capsule().strokeBorder(TwofoldDark.Line.strong, lineWidth: 1.25)
                            }
                        }
                }
                .buttonStyle(.plain)
                // Floating badge (hovering over the pill's corner) rather than sitting inline
                // next to the label — inline was eating into the widest pill's share of the
                // equal-width row, forcing every label down to a smaller, shrink-to-fit font size.
                // Only "Your turn" gets a count — that's the one actionable bucket; a number on
                // "Answered"/"New" doesn't prompt anything, just adds noise next to it.
                .overlay(alignment: .topTrailing) {
                    if filter == .yourTurn, let count = deckBrowseFilterCounts[filter], count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.heartRed, in: Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
            }
        }
    }

    /// How many decks fall into each `DeckBrowseFilter` bucket right now — shown as the small
    /// number bubble on each pill above, same bucketing `AllDecksBrowseView` uses so the counts
    /// promise exactly what tapping through to that filter will show.
    private var deckBrowseFilterCounts: [DeckBrowseFilter: Int] {
        guard let decks = appModel.gameDecks else { return [:] }
        var counts: [DeckBrowseFilter: Int] = [:]
        for deck in decks {
            counts[DeckBrowseFilter.bucket(for: deck, progress: appModel.deckProgress), default: 0] += 1
        }
        return counts
    }

    /// The four conversation games.
    ///
    /// This used to be one swipeable row holding every type, and by the ninth card that had stopped
    /// working — four swipe comfortably and nine bury the last five. Splitting them is not a new
    /// Compete/Connect divide: that grouping failed because it was a category nobody outside the
    /// screen ever saw. This one is a difference people already know without being taught — these
    /// four are questions about the two of you, backed by decks to browse, and the ones below are
    /// puzzles.
    private var conversationGamesSection: some View {
        section("Questions & Conversation", games: GameType.allCases.filter(\.hasDecks))
    }

    /// The five generated and board games.
    private var puzzlesSection: some View {
        section("Puzzles & Games", games: GameType.allCases.filter { !$0.hasDecks })
    }

    /// Both lists, in one format.
    ///
    /// They were different shapes — a scrolling row of big cards and a grid of the same big cards —
    /// which made two groups of the same kind of thing look like two kinds of thing. One format
    /// says what the split actually is: same games, different subject.
    ///
    /// Two columns of compact tiles rather than the 170pt cards. Nine of those came to over 700pt
    /// before anything else on the screen, so the travel decks and topics below were past two
    /// scrolls of nothing but names; this is the same nine in roughly a third of the height, with
    /// every one of them reachable without a horizontal swipe nobody knows to make.
    private func section(_ title: String, games: [GameType]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm),
                          GridItem(.flexible(), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                ForEach(games) { gameType in
                    tile(for: gameType)
                }
            }
        }
    }

    /// One tile, and where it goes.
    ///
    /// The destinations used to be an if/else chain inside the row, one branch per game, and by the
    /// ninth it was long enough that adding a game meant reading all of it. The lock is the same in
    /// both sections: a tile that needs a partner opens the invite sheet rather than doing nothing,
    /// because a lock badge with no action just teaches people the tile is broken.
    @ViewBuilder
    private func tile(for gameType: GameType) -> some View {
        if gameType.requiresPartner && !appModel.partnerConnected {
            Button {
                showingPartnerGate = true
            } label: {
                GameTile(gameType: gameType, isLocked: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                entryView(for: gameType)
            } label: {
                GameTile(gameType: gameType)
            }
            .buttonStyle(.plain)
        }
    }

    /// Where a game type's card leads.
    ///
    /// The deck games open their deck list. The other five have no decks, so each opens the small
    /// screen standing in for one — a difficulty, a theme, today's word, or a board. Chess opens
    /// even without Premium: its entry screen explains what it is and offers the paywall, where a
    /// card that refused to open would only teach people it is broken.
    @ViewBuilder
    private func entryView(for gameType: GameType) -> some View {
        switch gameType {
        case .sudoku: SudokuDifficultyPickerView()
        case .wordGuess: WordGuessEntryView()
        case .wordSearch: WordSearchThemePickerView()
        case .connectFour: ConnectFourEntryView()
        case .chess: ChessEntryView()
        case .triviaBattle, .moreLikely, .thisOrThat, .deepConversations:
            GameTypeDecksView(gameType: gameType)
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

            if appModel.gameDecks == nil {
                // `loadGameDecksIfNeeded()` (below) hasn't resolved yet — `travelDecks` reads as
                // empty either way, so without this a returning user with real decks would see
                // an empty carousel flash before their actual cards pop in. Sized to roughly
                // match a real `DeckCardRow` so the swap-in doesn't visibly jump.
                ProgressView()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
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
}

#Preview {
    GamesHubView()
        .environment(AppModel())
}
