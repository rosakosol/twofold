//
//  GameHistoryView.swift
//  Twofold
//
//  Completed sessions, reachable from the Games hub. Tapping a row reopens the same typed
//  game view used for live play — each one checks `GameSessionStore.isRevealed` first and
//  routes straight to `GameResultsView` for a completed session, so no separate read-only
//  code path is needed here.
//

import PostHog
import SwiftUI

struct GameHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sessions: [GameSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Trivia sessions' scores and daily-question sessions' actual question text — both need a
    /// full `GameSessionDetail` fetch (rounds/content/responses) that the plain session list
    /// doesn't carry, so they're loaded separately, in parallel, and only for the sessions that
    /// actually need it (every other game type/session shows fine from the list alone).
    @State private var scores: [UUID: (mine: Int, partner: Int)] = [:]
    @State private var dailyQuestionText: [UUID: String] = [:]
    /// nil = every game type. Independent of `dailyOnly` below — the two combine (e.g. "Trivia
    /// Battle" + daily-only yields nothing, since only Deep Conversations sessions are ever
    /// daily), rather than one being a sub-option of the other.
    @State private var selectedGameType: GameType?
    @State private var dailyOnly = false

    private var filteredSessions: [GameSession] {
        sessions.filter { session in
            if let selectedGameType, session.gameType != selectedGameType { return false }
            if dailyOnly, !session.isDaily { return false }
            return true
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: Theme.Spacing.sm) {
                    GameErrorState(message: errorMessage)
                    Button("Try again") { Task { await load() } }
                }
            } else if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        filterRow

                        if filteredSessions.isEmpty {
                            filteredEmptyState
                        } else {
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredSessions) { session in
                                    NavigationLink {
                                        gameDestination(session: session)
                                    } label: {
                                        historyRow(session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Completed games")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await appModel.loadGameDecksIfNeeded() }
        .postHogScreenView("Games: History")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text("No completed games yet")
                .font(.headline)
            Text("Finish a game together and it'll show up here.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown instead of the row list when filters narrow `sessions` down to nothing — distinct
    /// from `emptyState` above, which only covers there being no completed games at all.
    private var filteredEmptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text("No games match these filters")
                .font(.headline)
            Button("Clear filters") {
                selectedGameType = nil
                dailyOnly = false
            }
            .font(.caption.weight(.semibold))
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// Mirrors `AllDecksBrowseView.filterPill`'s pill styling for visual consistency across the
    /// Games feature's two filter UIs. `dailyOnly` is a plain toggle rather than a member of the
    /// same mutually-exclusive set as the game-type pills — see `dailyOnly`'s own doc comment.
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterPill(isSelected: selectedGameType == nil, label: "All") { selectedGameType = nil }
                ForEach(GameType.allCases) { type in
                    filterPill(isSelected: selectedGameType == type, label: type.displayName) { selectedGameType = type }
                }
                filterPill(isSelected: dailyOnly, label: "Daily Question") { dailyOnly.toggle() }
            }
        }
    }

    private func filterPill(isSelected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .background(
                    isSelected ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.cardBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func historyRow(_ session: GameSession) -> some View {
        let deck = deck(for: session)
        let topic = deck.flatMap { GameTopic(rawValue: $0.topic) }
        return SectionCard {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: session.gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: session.gameType.icon).foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    if session.isDaily {
                        PillBadge(text: "Daily Deep Question", tint: Theme.heartRed)
                    } else if let topic {
                        PillBadge(text: topic.displayName, tint: topic.color)
                    }
                    // The daily question's own text takes priority over the deck's own title
                    // (e.g. "How Well Do You Know European History?") — a daily session has no
                    // deck to name it after, and the actual question is the more useful thing to
                    // show anyway. Falls back to the generic game type name for older, pre-deck
                    // sessions with no deckID or resolved question text to show instead.
                    Text(session.isDaily ? (dailyQuestionText[session.id] ?? session.gameType.displayName) : (deck?.title ?? session.gameType.displayName))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(session.gameType.displayName)
                        Text("•")
                        Text(completionDate(for: session), format: .dateTime.day().month(.abbreviated).year())
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    // Trivia is the one game type with an actual right/wrong score — the match
                    // games show a match percentage instead (on the results screen itself, not
                    // here), and Deep Conversations has no score concept at all.
                    if let score = scores[session.id] {
                        Text("\(appModel.currentUser.name) \(score.mine) · \(appModel.partner.name) \(score.partner)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.skyBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
    }

    private func deck(for session: GameSession) -> GameDeck? {
        session.deckID.flatMap { deckID in appModel.gameDecks?.first(where: { $0.id == deckID }) }
    }

    @ViewBuilder
    private func gameDestination(session: GameSession) -> some View {
        let deck = deck(for: session)
        gameDestinationView(gameType: session.gameType, sessionID: session.id, title: deck?.title, topic: deck?.topic)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await BackendService.fetchGameSessions(status: .completed)
            // Most recently completed first — `.filter` above preserves order, so sorting here
            // once is enough for `filteredSessions` (and the row list built from it) too.
            sessions = GameLogic.completedSessionsOnly(all).sorted { completionDate(for: $0) > completionDate(for: $1) }
            await loadExtraDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Falls back to `updatedAt` for the rare completed session missing `completedAt` — a
    /// completed row's last write is, in practice, the moment it was marked complete, so this
    /// keeps both the sort and the displayed date meaningful instead of silently having neither.
    private func completionDate(for session: GameSession) -> Date {
        session.completedAt ?? session.updatedAt
    }

    /// Fetches full session detail — concurrently, one request per session — only for trivia
    /// sessions (score) and daily-question sessions (actual question text), since every other
    /// session already has everything `historyRow` needs from the plain session list.
    private func loadExtraDetails() async {
        let needsDetail = sessions.filter { $0.gameType == .triviaBattle || $0.isDaily }
        guard !needsDetail.isEmpty else { return }
        await withTaskGroup(of: (UUID, BackendService.GameSessionDetail?).self) { group in
            for session in needsDetail {
                group.addTask {
                    let detail = try? await BackendService.fetchGameSession(id: session.id)
                    return (session.id, detail)
                }
            }
            for await (sessionID, detail) in group {
                guard let detail, let session = sessions.first(where: { $0.id == sessionID }) else { continue }
                if session.gameType == .triviaBattle {
                    scores[sessionID] = (
                        mine: GameLogic.triviaScore(responses: detail.responses, responderID: appModel.currentUser.id),
                        partner: GameLogic.triviaScore(responses: detail.responses, responderID: appModel.partner.id)
                    )
                }
                if session.isDaily, let round = detail.rounds.first, case .deepConversation(let topic)? = detail.content[round.contentID] {
                    dailyQuestionText[sessionID] = topic.topic
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GameHistoryView()
    }
    .environment(AppModel())
}
