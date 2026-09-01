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
    @Environment(\.colorScheme) private var colorScheme
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
    /// True when the couple has more completed games than `historyLimit`, so the list below is a
    /// truncation rather than the whole record — worth saying out loud instead of just stopping.
    @State private var reachedHistoryLimit = false
    /// How many rows have been requested, including ones `completedSessionsOnly` dropped — the
    /// paging offset has to count what the server returned, not what survived filtering.
    @State private var rawSessionCount = 0
    /// True while a further page is on its way, so the footer can say so and the trigger can't
    /// fire twice for the same page.
    @State private var isLoadingMore = false
    /// False once a page comes back short, meaning there's nothing after it.
    @State private var hasMore = true

    /// How many completed games arrive per page.
    ///
    /// This screen used to fetch the whole history at once and then fetch full detail for most of
    /// it — the daily question alone produces a session a day, so a couple six months in waited on
    /// ~180 rows plus ~180 detail requests before seeing anything. A page is about two screens'
    /// worth, so the first one lands quickly and the rest arrive as they're scrolled to.
    private static let pageSize = 25

    /// The ceiling across all pages. Unbounded, paging would eventually walk into PostgREST's own
    /// `max_rows` of 1000 and start dropping rows with no signal. Newest-first, so what's cut is
    /// the oldest.
    private static let historyLimit = 200

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
                                    .onAppear {
                                        // Triggered from the last row rather than a scroll offset:
                                        // the filters above can shrink the list to a handful, and
                                        // an offset threshold would then never be reached while
                                        // more pages sat unfetched behind the filter.
                                        if session.id == filteredSessions.last?.id {
                                            Task { await loadMore() }
                                        }
                                    }
                                }
                            }

                            listFooter
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

    @ViewBuilder
    private var listFooter: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.sm)
        } else if reachedHistoryLimit {
            Text("Showing your \(Self.historyLimit) most recent games.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xs)
        }
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
                // Without these the enclosing horizontal ScrollView proposes each pill a width
                // narrow enough to wrap its label — at accessibility text sizes that degenerates
                // into one letter per line and a column of very tall capsules. Pinned to their
                // natural single-line width, the row scrolls instead, which is what it's for.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .background(
                    isSelected ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.cardBackground),
                    in: Capsule()
                )
                // Unselected pills had no edge of their own in dark mode — plain neutral
                // hairline, same as the Games hub's own filter pills (this is a filter choice,
                // not a blue/green/red state, so no colored gradient here).
                .overlay {
                    if !isSelected && colorScheme == .dark {
                        Capsule().strokeBorder(TwofoldDark.Line.strong, lineWidth: 1.25)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func historyRow(_ session: GameSession) -> some View {
        let deck = deck(for: session)
        let topic = deck.flatMap { GameTopic(rawValue: $0.topic) }
        return SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if session.isDaily {
                        PillBadge(text: "Daily Deep Question", tint: Theme.heartRed)
                    } else if let topic {
                        PillBadge(text: topic.displayName, tint: topic.color, isNeutral: true)
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
                // The deck's own emoji instead of the generic game-type symbol — a daily
                // question has no deck to pull one from, so it just falls back to showing
                // nothing here rather than a placeholder glyph.
                if let emoji = deck?.emoji {
                    Text(emoji).font(.title2)
                }
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

    /// The first page. Only this one shows the full-screen spinner; every page after it arrives
    /// under the list without taking the screen away.
    private func load() async {
        guard sessions.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        hasMore = true
        reachedHistoryLimit = false
        await fetchPage()
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading, errorMessage == nil else { return }
        isLoadingMore = true
        await fetchPage()
        isLoadingMore = false
    }

    /// Fetches the page after whatever's already loaded and appends it.
    ///
    /// The offset is `rawSessionCount`, not `sessions.count`: `completedSessionsOnly` can drop rows
    /// from a page, and paging on the kept count would re-request the dropped ones forever, serving
    /// the same page over and over.
    private func fetchPage() async {
        do {
            let page = try await BackendService.fetchGameSessions(
                status: .completed,
                limit: Self.pageSize,
                offset: rawSessionCount
            )
            rawSessionCount += page.count

            // A short page means the server has nothing more.
            if page.count < Self.pageSize { hasMore = false }

            let newlyCompleted = GameLogic.completedSessionsOnly(page)
                .filter { session in !sessions.contains { $0.id == session.id } }

            // Sorted across the whole list, not just the new page: `updated_at` orders the fetch
            // (stable, always populated) while `completedAt` orders the display, and the two can
            // disagree — so a later page can legitimately contain a game that belongs above one
            // already on screen.
            sessions = (sessions + newlyCompleted).sorted { completionDate(for: $0) > completionDate(for: $1) }

            if sessions.count >= Self.historyLimit {
                sessions = Array(sessions.prefix(Self.historyLimit))
                reachedHistoryLimit = true
                hasMore = false
            }

            await loadExtraDetails(for: newlyCompleted)
        } catch {
            // Only fatal for the first page. A later one failing leaves what's already on screen
            // alone and simply stops paging, rather than replacing a working list with an error.
            if sessions.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                hasMore = false
            }
        }
    }

    /// Falls back to `updatedAt` for the rare completed session missing `completedAt` — a
    /// completed row's last write is, in practice, the moment it was marked complete, so this
    /// keeps both the sort and the displayed date meaningful instead of silently having neither.
    private func completionDate(for session: GameSession) -> Date {
        session.completedAt ?? session.updatedAt
    }

    /// How many detail requests may be in flight at once. Previously every qualifying session was
    /// dispatched at the same instant, which is fine for a new couple and much less so later: the
    /// daily question produces one session per day, so six months in this screen opened ~180
    /// simultaneous requests, each pulling a session's rounds, content and responses. That's a
    /// stall on a good connection and a pile of timeouts on a bad one. A small window keeps the
    /// screen filling in steadily instead.
    private static let detailFetchConcurrency = 6

    /// Fetches full session detail — a few requests at a time — only for trivia sessions (score)
    /// and daily-question sessions (actual question text), since every other session already has
    /// everything `historyRow` needs from the plain session list.
    ///
    /// Scoped to one page's sessions rather than the whole list. It used to run across everything
    /// loaded, so each new page re-requested detail for every session already on screen — work that
    /// grew with the list and that had already been done.
    private func loadExtraDetails(for pageSessions: [GameSession]) async {
        let needsDetail = pageSessions.filter { $0.gameType == .triviaBattle || $0.isDaily }
        guard !needsDetail.isEmpty else { return }
        await withTaskGroup(of: (UUID, BackendService.GameSessionDetail?).self) { group in
            var pending = needsDetail.makeIterator()

            func addNext() -> Bool {
                guard let session = pending.next() else { return false }
                group.addTask {
                    let detail = try? await BackendService.fetchGameSession(id: session.id)
                    return (session.id, detail)
                }
                return true
            }

            for _ in 0..<Self.detailFetchConcurrency {
                if !addNext() { break }
            }

            // Each completion immediately starts the next request, so the window stays full
            // without ever exceeding it.
            while let (sessionID, detail) = await group.next() {
                _ = addNext()
                guard let detail, let session = pageSessions.first(where: { $0.id == sessionID }) else { continue }
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
