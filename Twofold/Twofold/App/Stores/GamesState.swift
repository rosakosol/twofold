//
//  GamesState.swift
//  Twofold
//
//  The Games hub's state: today's Daily Activity question, the streak and its repair offer, the
//  decks and the couple's progress through them, and the 18+ opt-in. Owned by `AppModel`, which
//  forwards the old property names to it.
//

import Foundation
import Observation

@Observable
final class GamesState: AccountScopedStore {
    /// Daily Activity streak — see `startOrResumeDailyQuestion()`/`refreshDailyStreak()`. Nil
    /// until the first fetch resolves (not defaulted to 0) so `DailyActivityCard` can show a
    /// placeholder instead of visibly flashing "Start a streak" before the real value loads.
    var dailyStreak: Int?
    var longestDailyStreak: Int?
    /// The instant the daily question/streak next rolls over — real local midnight, resolved
    /// server-side (see `BackendService.fetchDailyStreak`). Nil until the first fetch lands.
    var dailyStreakResetsAt: Date?
    /// Whether a streak that just ended can still be bought back, and what it was worth. Nil until
    /// looked up and left nil when the lookup fails — no offer is better than a wrong one.
    var streakRepair: BackendService.StreakRepairState?
    /// Today's Daily Activity session id, once known (fetched lazily, not at launch — see
    /// `startOrResumeDailyQuestion()`).
    var todaysDailySessionID: UUID?
    /// The actual discussion topic text for today's session — shown on `DailyActivityCard`
    /// instead of a generic teaser line. Nil while loading or if the fetch fails.
    var todaysDailyQuestionText: String?
    /// True while `startOrResumeDailyQuestion()` is in flight.
    ///
    /// `todaysDailyQuestionText == nil` can't stand in for this: it's ambiguous, covering both
    /// "hasn't been fetched yet" and "the fetch finished but the topic couldn't be resolved" (the
    /// inner `try?` in that method). `DailyActivityCard` has to tell those apart — the first
    /// deserves a skeleton, the second deserves the generic teaser rather than a placeholder that
    /// never resolves.
    private(set) var isLoadingDailyQuestion = false
    /// Per-partner completion for today's question — drives the checkmark on each avatar in
    /// `DailyActivityCard`. See `get_daily_question_status` for why this needs its own
    /// RLS-bypassing RPC rather than reading `game_responses` directly.
    var todaysMyAnswered = false
    var todaysPartnerAnswered = false
    /// Set when `startOrResumeDailyQuestion()` fails to obtain a session id — lets
    /// `DailyActivityCard` show a real error state instead of spinning forever on a
    /// `ProgressView` that's silently waiting on data that will never arrive.
    var dailyQuestionError: String?

    /// All active decks + which ones this couple has started, cached after first load
    /// (`loadGameDecksIfNeeded()`) — powers the Games hub's topic list and progress bars. Not
    /// loaded at app launch; only Games-hub visits need it.
    private(set) var gameDecks: [GameDeck]?
    /// True once a deck fetch has been attempted and failed — see `refreshGameDecks`.
    private(set) var gameDecksUnavailable = false
    /// Per-deck completion counts for the couple — see `DeckProgress`/`get_deck_progress()`.
    /// Superseded `playedDeckIDs` (a deck has progress here the moment either partner starts it).
    private(set) var deckProgress: [UUID: DeckProgress]?
    /// Where each partner stands on 18+ questions — see `setAdultContentOptIn(_:)`. Nil until
    /// Settings asks.
    private(set) var adultContentStatus: BackendService.AdultContentStatus?
    /// Set by the Daily Question widget's link and the daily question push, and consumed by
    /// `DailyActivityCard`, which opens today's question and clears it. A flag rather than a
    /// navigation call because the card may not be on screen yet: the Games tab is still appearing
    /// when the link arrives.
    var isDailyQuestionOpenRequested = false

    /// Whether a partner has joined. Only a couple has a streak to repair.
    @ObservationIgnored var isPartnerConnected: () -> Bool = { false }
    /// Called once today's question has been fetched, so the widget can show it.
    @ObservationIgnored var onDailyQuestionChanged: () -> Void = {}

    func reset() {
        // Otherwise `loadGameDecksIfNeeded()`'s nil-guard treats this account's Games hub as
        // already loaded and shows the previous account's deck progress until something else
        // happens to call `refreshGameDecks()` unconditionally.
        gameDecks = nil
        deckProgress = nil
        adultContentStatus = nil

        // Also reported: the streak flickering from the previous couple's 28 days to the new
        // account's real value once the fetch landed.
        dailyStreak = nil
        longestDailyStreak = nil
        dailyStreakResetsAt = nil
        streakRepair = nil

        // The previous couple's daily question, and whether the two of them had answered it.
        todaysDailySessionID = nil
        todaysDailyQuestionText = nil
        todaysMyAnswered = false
        todaysPartnerAnswered = false
        dailyQuestionError = nil

        // The previous account's failed deck fetch, and a widget link or push asking to open the
        // previous couple's question, which the next account's Games tab would otherwise act on.
        gameDecksUnavailable = false
        isDailyQuestionOpenRequested = false
    }

    /// The streak and today's question, restored the same way and for the same reason as the rest:
    /// they're only ever set by a backend call, so offline they sat at zero and nil.
    func applyCachedGameState() {
        guard let cached = OfflineGameStateCache.restore(for: BackendService.currentUserID) else { return }
        if dailyStreak == nil { dailyStreak = cached.dailyStreak }
        if longestDailyStreak == nil { longestDailyStreak = cached.longestDailyStreak }
        if dailyStreakResetsAt == nil { dailyStreakResetsAt = cached.dailyStreakResetsAt }
        if todaysDailyQuestionText == nil {
            todaysDailyQuestionText = cached.questionText
            todaysDailySessionID = cached.questionSessionID
            todaysMyAnswered = cached.myAnswered
            todaysPartnerAnswered = cached.partnerAnswered
        }
        if deckProgress == nil { deckProgress = cached.deckProgress }
    }


    /// Fetches (or creates, server-side) today's Daily Activity session and refreshes the
    /// streak — called when the Games hub appears, not at launch, since it's Games-specific.
    func startOrResumeDailyQuestion() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        dailyQuestionError = nil
        isLoadingDailyQuestion = true
        defer { isLoadingDailyQuestion = false }

        // Today's cache, painted before any network work rather than only as a fallback.
        //
        // This used to be reached solely when offline or on a thrown error, so on a slow-but-working
        // connection the card sat on its skeleton for the whole chain below even though the answer
        // was already on disk. It is safe to lead with because the cache is day-scoped and the
        // backend assigns one question per day, so a question recorded earlier today *is* today's
        // question — see `OfflineGameStateCache`'s own header. `reportMissing: false` because
        // having no cache is the normal first-run state, not an error to show someone.
        applyCachedDailyQuestion(reportMissing: false)

        // Same reason as `refreshGameDecks`: offline these calls only fail, and only after a full
        // timeout each, so the card spun for a minute before showing the question already cached
        // from earlier today.
        guard NetworkMonitor.shared.isConnected else {
            applyCachedDailyQuestion()
            return
        }
        // One call for the question, concurrent with the streak.
        //
        // This used to be the session id, then `fetchGameSession(id:)` for the text, then the
        // answered flags — and the middle one is the generic detail loader, which is four
        // sequential queries of its own. Five round trips deep for one sentence, each waiting
        // out the last, which is what made the card take seconds on a working connection.
        // `get_daily_question` (20261110001700) returns the lot in one row.
        //
        // The streak stays a separate call rather than being folded in: it is per couple rather
        // than per question, `refreshAll()` fetches it on its own for the Home card, and it
        // awaits the repair state after itself. Running it alongside costs nothing, and the card
        // draws the question without waiting for it.
        async let question = try? BackendService.fetchDailyQuestion()
        async let streakRefreshed: Void = refreshDailyStreak()

        if let question = await question {
            todaysDailySessionID = question.sessionID
            todaysDailyQuestionText = question.question
            todaysMyAnswered = question.mine
            todaysPartnerAnswered = question.partner
        }
        await streakRefreshed
        recordGameStateForOffline()
        // The Daily question widget reads this state; the snapshot is otherwise only rewritten on
        // launch and on other changes, so an answer would not reach the Home Screen until then.
        onDailyQuestionChanged()
    }

    /// Only asked when there is plainly something to ask about: a streak reading zero. The
    /// repairable window needs the couple's own local dates to evaluate, so it is a round trip, and
    /// a couple mid-streak has no use for the answer.
    func refreshStreakRepairState() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard NetworkMonitor.shared.isConnected, isPartnerConnected(), dailyStreak == 0 else {
            streakRepair = nil
            return
        }
        streakRepair = try? await BackendService.streakRepairState()
    }

    func refreshDailyStreak() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        // `refreshAll()` runs this alongside five other fetches on every foreground and every
        // pull-to-refresh; offline it can only wait out a timeout, holding that whole group open.
        guard NetworkMonitor.shared.isConnected else { return }
        if let streak = try? await BackendService.fetchDailyStreak() {
            dailyStreak = streak.current
            longestDailyStreak = streak.longest
            dailyStreakResetsAt = streak.resetsAt
            recordGameStateForOffline()
        }
        await refreshStreakRepairState()
    }

    /// Today's question as of the last time it was fetched. The backend assigns one per day, so a
    /// question cached earlier today is the same question, not a guess at it — which is why this
    /// only restores one recorded today, and reports a real error otherwise.
    /// `reportMissing` distinguishes the two callers. As a fallback, no cache means there is nothing
    /// to show and the error is the honest outcome. As the opening paint, no cache is simply a first
    /// run, and an error there would flash before the network had been given a chance.
    private func applyCachedDailyQuestion(reportMissing: Bool = true) {
        if let cached = OfflineGameStateCache.restore(for: BackendService.currentUserID),
           let text = cached.questionText {
            todaysDailyQuestionText = text
            todaysDailySessionID = cached.questionSessionID
            todaysMyAnswered = cached.myAnswered
            todaysPartnerAnswered = cached.partnerAnswered
            if dailyStreak == nil { dailyStreak = cached.dailyStreak }
            if longestDailyStreak == nil { longestDailyStreak = cached.longestDailyStreak }
            if dailyStreakResetsAt == nil { dailyStreakResetsAt = cached.dailyStreakResetsAt }
        } else if reportMissing {
            dailyQuestionError = "Today's question needs a connection. Decks below are ready to play."
        }
    }

    /// Keeps the streak and today's question on disk so the Games hub has something to show with
    /// no network — otherwise a 40-day streak read as zero, which is the one number in the app
    /// nobody wants to see wrong.
    func recordGameStateForOffline() {
        OfflineGameStateCache.record(
            dailyStreak: dailyStreak,
            longestDailyStreak: longestDailyStreak,
            dailyStreakResetsAt: dailyStreakResetsAt,
            questionText: todaysDailyQuestionText,
            questionSessionID: todaysDailySessionID,
            myAnswered: todaysMyAnswered,
            partnerAnswered: todaysPartnerAnswered,
            deckProgress: deckProgress,
            userID: BackendService.currentUserID
        )
    }

    /// Populates `gameDecks`/`deckProgress` once per app session (cheap to recheck — both are
    /// simple nil-guards) for the Games hub's topic list and progress bars.
    func loadGameDecksIfNeeded() async {
        guard gameDecks == nil else { return }
        await refreshGameDecks()
    }

    /// Re-fetches unconditionally — called after starting/resetting a deck session so its
    /// progress updates immediately rather than waiting for the next cold load.
    func refreshGameDecks() async {
        // Straight to the on-device catalogue when there's nothing to ask. Both fetches below take
        // a full URLSession timeout to fail offline, and the hub shows a spinner until they do —
        // a minute of waiting to be handed decks that were on the device the whole time.
        // -demoMode takes the on-device catalogue too: there is no account to ask.
        guard NetworkMonitor.shared.isConnected, !DemoMode.isOn else {
            gameDecks = nonEmpty(decksShown(GameContentStore.decks()))
            gameDecksUnavailable = gameDecks?.isEmpty ?? true
            // Every topic bar on the hub is counted from this. Left nil it reads as zero decks
            // completed — telling a couple who has finished forty of them that they have finished
            // none, which is the same thing the streak used to do.
            if deckProgress == nil {
                deckProgress = OfflineGameStateCache.restore(for: BackendService.currentUserID)?.deckProgress
            }
            return
        }
        async let decks = BackendService.fetchGameDecks()
        async let progress = BackendService.fetchDeckProgress()
        let fetchedDecks = try? await decks
        // Falls back to the on-device catalogue rather than to nothing. Decks are the entry point
        // to every game, so with no network this was an empty hub — the screen a couple reaches
        // on the flight where they have hours and nothing else to do. `GameContentStore` carries
        // the same decks, from the bundled seed or from the last online refresh.
        // Before filtering: whether 18+ decks are shown depends on it, and on a first load nothing
        // has asked yet.
        if adultContentStatus == nil, (fetchedDecks ?? []).contains(where: \.isAdult) {
            await refreshAdultContentStatus()
        }
        gameDecks = (fetchedDecks.map(decksShown)).flatMap(nonEmpty) ?? nonEmpty(decksShown(GameContentStore.decks()))
        deckProgress = try? await progress
        if deckProgress != nil { recordGameStateForOffline() }
        // Distinguishes "haven't asked yet" from "asked and there's nothing to show", which
        // `gameDecks == nil` alone can't. Without it `RecommendedGamesSection` showed its loading
        // spinner forever whenever the fetch failed. Now that the fetch failing still leaves the
        // on-device catalogue, this is only true when *both* are empty — a failed fetch with decks
        // on disk isn't an unavailable state any more, it's just offline.
        // Deliberately not driven off `NetworkMonitor` alone: NWPathMonitor reports "connected" on
        // a captive portal or when the server itself is down, both of which strand the spinner
        // just the same.
        gameDecksUnavailable = gameDecks?.isEmpty ?? true
        // Detached, never awaited. This pulls the whole catalogue — four tables, ~2,000 rows, about
        // half a megabyte — and awaiting it here put all of that in front of the Games hub's first
        // paint, and in front of every `refreshAll()`. The decks it needs are already assigned
        // above; this only refreshes the offline copy for later, so nothing on screen is waiting
        // on it.
        Task.detached(priority: .background) { await Self.refreshGameContentIfStale() }
    }

    /// 18+ decks only once both partners have opted in.
    ///
    /// The server already holds them back from everyone else (20261113000900), so for nearly every
    /// account this removes nothing. It exists for the accounts the server does show them to:
    /// content admins, whose admin policy reads every deck so the console can manage them. The app
    /// signs in as the same account, so without this an admin saw After Dark with the switch off.
    /// It also covers an offline copy cached before somebody opted out. Unknown status hides them.
    private func decksShown(_ decks: [GameDeck]) -> [GameDeck] {
        let unlocked = adultContentStatus?.isUnlocked ?? false
        return decks.filter { !$0.isAdult || unlocked }
    }

    /// Empty means "the fetch produced nothing", which is not a usable fallback — keep nil so the
    /// caller can tell the difference.
    private func nonEmpty(_ decks: [GameDeck]) -> [GameDeck]? {
        decks.isEmpty ? nil : decks
    }

    func refreshAdultContentStatus() async {
        adultContentStatus = try? await BackendService.fetchAdultContentStatus()
    }

    /// Opts this person in or out of 18+ questions, then brings the decks and the offline copy in
    /// line straight away rather than at the next daily refresh: opting in should show the decks
    /// as soon as the partner has too, and opting out should take them off this device now, not
    /// tomorrow.
    func setAdultContentOptIn(_ isOn: Bool) async throws {
        try await BackendService.setAdultContentOptIn(isOn)
        await refreshAdultContentStatus()
        await refreshGameDecks()
        if let payload = try? await BackendService.fetchGameContentPayload() {
            GameContentStore.store(payload: payload)
        }
    }

    /// Pulls the full deck-and-content catalogue onto the device so games work with no network.
    ///
    /// Daily, not per foreground: it's about half a megabyte, and content changes on the order of
    /// weeks. The first run after an install has no cached copy at all and fetches immediately —
    /// until then the app is running on the bundled seed, which is only as current as the last
    /// release.
    private static func refreshGameContentIfStale() async {
        guard NetworkMonitor.shared.isConnected else { return }
        if let age = GameContentStore.cacheAge, age < 24 * 60 * 60 { return }
        guard let payload = try? await BackendService.fetchGameContentPayload() else { return }
        GameContentStore.store(payload: payload)
    }

    /// Flips this deck's own "Your turn" → "Answered" bucket instantly, without waiting on
    /// `refreshGameDecks()`'s network round trip — called the moment `GameResultsView`/
    /// `GameCompletionView` appear, alongside (not instead of) that same refresh, which still
    /// runs to pick up the partner's own side. Without this, "Your turn" stayed stale for however
    /// long that fetch took, which read as "finishing a game doesn't count" until the user left
    /// and came back to the Games tab and the fetch had finally landed by then.
    func markDeckProgressMineCompleted(deckID: UUID?) {
        guard let deckID, var progress = deckProgress?[deckID] else { return }
        let wasCompleted = progress.bothCompleted
        progress.myAnswered = progress.totalRounds
        // My side being the one that finishes the deck makes *now* its completion moment — the
        // same stamp `advance_game_session_status` writes server-side. Without it the row keeps
        // whatever `completed_at`/`updated_at` the last fetch happened to carry, which sorted the
        // deck I just finished into the middle of the Answered list (and printed that stale date
        // on its card) until `refreshGameDecks()`' round trip landed.
        if !wasCompleted, progress.bothCompleted {
            progress.completedAt = .now
        }
        deckProgress?[deckID] = progress
    }

    /// All of this topic's decks, in curated order — Plus members see Premium-tier decks too now
    /// (they just show an unlock badge, see `isDeckLocked(_:)`), so this no longer filters by
    /// tier the way it originally did.
    func decks(for topic: GameTopic) -> [GameDeck] {
        (gameDecks ?? [])
            .filter { $0.topic == topic.rawValue }
            .sorted { $0.sortOrder < $1.sortOrder }
    }


    /// Every deck of this game type, across every topic — powers "tap a game type card, see all
    /// its decks" browsing, as opposed to `decks(for topic:)`'s single-topic scoping.
    func decks(ofType gameType: GameType) -> [GameDeck] {
        (gameDecks ?? []).filter { $0.gameType == gameType }
    }

    /// How many of this topic's decks the couple has actually finished — `nil` until
    /// `loadGameDecksIfNeeded()` has completed.
    ///
    /// Counts completed decks rather than started ones. Started was doubly misleading: opening a
    /// deck creates its session before a single question is answered, so the bar crept up for
    /// decks nobody had played, and even a genuinely half-played deck read as full credit toward
    /// the topic.
    func topicProgress(_ topic: GameTopic) -> (played: Int, total: Int)? {
        guard gameDecks != nil else { return nil }
        let topicDecks = decks(for: topic)
        guard !topicDecks.isEmpty else { return nil }
        let progress = deckProgress ?? [:]
        let playedCount = topicDecks.filter { progress[$0.id]?.isCompleted ?? false }.count
        return (playedCount, topicDecks.count)
    }

    #if DEBUG
    func markDecksUnavailableForTesting() {
        gameDecksUnavailable = true
    }

    /// The sample couple's games, for `-demoMode` (see `AppModel.applyDemoState()`).
    func applyDemoState() {
            dailyStreak = DemoData.streak
            longestDailyStreak = DemoData.streak
            dailyStreakResetsAt = Calendar.current.date(byAdding: .hour, value: 14, to: .now)
            todaysDailySessionID = UUID()
            todaysDailyQuestionText = DemoData.dailyQuestion
            todaysMyAnswered = true
            todaysPartnerAnswered = true
            gameDecks = nonEmpty(GameContentStore.decks())
            gameDecksUnavailable = gameDecks?.isEmpty ?? true
            deckProgress = [:]
    }
    #endif
}
