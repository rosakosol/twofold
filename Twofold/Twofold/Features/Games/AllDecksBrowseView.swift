//
//  AllDecksBrowseView.swift
//  Twofold
//
//  Search + status-filter browsing across every deck, every topic, every game type — reached
//  from GamesHubView's search bar / "Your turn" / "New" / "Answered" pills. Distinct from
//  TopicDetailView/GameTypeDecksView's narrower Unanswered/Answered split: this is the one place
//  status is 3-way (New vs. Your turn vs. Answered), matching what the top-level pills promise.
//

import SwiftUI

enum DeckBrowseFilter: String, CaseIterable, Identifiable {
    case yourTurn = "Your turn"
    case new = "New"
    case answered = "Answered"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .yourTurn: "clock.fill"
        case .new: "sparkles"
        case .answered: "checkmark.circle.fill"
        }
    }
}

struct AllDecksBrowseView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var selectedFilter: DeckBrowseFilter?

    init(initialFilter: DeckBrowseFilter? = nil) {
        _selectedFilter = State(initialValue: initialFilter)
    }

    /// New = never started by either partner. Your turn = started, but I haven't finished my
    /// side yet. Answered = I've finished my side (regardless of whether my partner has) —
    /// mutually exclusive and exhaustive over every deck.
    private func bucket(for deck: GameDeck) -> DeckBrowseFilter {
        guard let progress = appModel.deckProgress?[deck.id] else { return .new }
        return progress.myCompleted ? .answered : .yourTurn
    }

    private var filteredDecks: [GameDeck] {
        var decks = appModel.gameDecks ?? []
        if let selectedFilter {
            decks = decks.filter { bucket(for: $0) == selectedFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            decks = decks.filter { $0.title.lowercased().contains(query) || $0.topic.lowercased().contains(query) }
        }
        return decks.sorted { lhs, rhs in
            let lhsStarted = appModel.deckProgress?[lhs.id] != nil
            let rhsStarted = appModel.deckProgress?[rhs.id] != nil
            if lhsStarted != rhsStarted { return lhsStarted }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.subtleInk)
                    TextField("Search games", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.cardBackground, in: Capsule())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        filterPill(nil, label: "All")
                        ForEach(DeckBrowseFilter.allCases) { filter in
                            filterPill(filter, label: filter.rawValue)
                        }
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(filteredDecks) { deck in
                        DeckCardRow(deck: deck, progress: appModel.deckProgress?[deck.id], showsTopicPill: true)
                    }
                }

                if filteredDecks.isEmpty {
                    Text("No games found.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("All Games")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appModel.loadGameDecksIfNeeded() }
    }

    private func filterPill(_ filter: DeckBrowseFilter?, label: String) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .foregroundStyle(selectedFilter == filter ? .white : Theme.ink)
                .background(
                    selectedFilter == filter ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.cardBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AllDecksBrowseView()
    }
    .environment(AppModel())
}
