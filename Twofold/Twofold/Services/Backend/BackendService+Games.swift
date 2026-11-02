//
//  BackendService+Games.swift
//  Twofold
//
//  Card-deck games, the daily question, streaks, deck progress, and game sessions.
//

import Foundation
import Supabase

extension BackendService {

    /// A couple's game sessions, for a data export.
    ///
    /// Its own fetch rather than `fetchGameSessions`, which is scoped to the signed-in user's
    /// *current* couple through RLS and returns the full in-app model. An export can be of a
    /// dissolved relationship, and needs only the handful of columns that go into games.csv.
    ///
    /// `rounds_completed` counts rounds whose discussion is finished; a session abandoned halfway
    /// should read as halfway rather than as complete.
    static func fetchExportedGameSessions(coupleID: UUID) async throws -> [ExportedGameSession] {
        struct Row: Decodable {
            var id: UUID
            var gameType: String
            var status: String
            var totalRounds: Int?
            var startedAt: Date?
            var createdAt: Date?
            var deckId: UUID?

            enum CodingKeys: String, CodingKey {
                case id, status
                case gameType = "game_type"
                case totalRounds = "total_rounds"
                case startedAt = "started_at"
                case createdAt = "created_at"
                case deckId = "deck_id"
            }
        }

        let rows: [Row] = try await supabase
            .from("game_sessions")
            .select("id,game_type,status,total_rounds,started_at,created_at,deck_id")
            .eq("couple_id", value: coupleID)
            .order("created_at", ascending: true)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        // Deck titles in one round trip rather than per session.
        struct DeckRow: Decodable { var id: UUID; var title: String }
        let deckIDs = Array(Set(rows.compactMap(\.deckId)))
        var titlesByID: [UUID: String] = [:]
        if !deckIDs.isEmpty {
            let decks: [DeckRow] = (try? await supabase
                .from("game_decks")
                .select("id,title")
                .in("id", values: deckIDs)
                .execute()
                .value) ?? []
            titlesByID = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0.title) })
        }

        struct RoundRow: Decodable {
            var sessionId: UUID
            var discussionStatus: String?
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case discussionStatus = "discussion_status"
            }
        }
        let rounds: [RoundRow] = (try? await supabase
            .from("game_session_rounds")
            .select("session_id,discussion_status")
            .in("session_id", values: rows.map(\.id))
            .execute()
            .value) ?? []
        var completedBySession: [UUID: Int] = [:]
        for round in rounds where round.discussionStatus == "completed" {
            completedBySession[round.sessionId, default: 0] += 1
        }

        return rows.map { row in
            ExportedGameSession(
                id: row.id,
                gameType: row.gameType,
                deckTitle: row.deckId.flatMap { titlesByID[$0] },
                startedAt: row.startedAt ?? row.createdAt,
                status: row.status,
                roundsCompleted: completedBySession[row.id] ?? 0,
                roundsTotal: row.totalRounds ?? 0
            )
        }
    }

    /// Whether a broken streak is still inside the window where it can be bought back, and what
    /// is at stake. See migration 20261007000000.
    struct StreakRepairState: Decodable {
        var repairable: Bool
        var streakAtRisk: Int
        var credits: Int
        /// A bare Postgres `date` ("2026-09-09"), kept as a string for the same reason
        /// `CoupleRow.startedDatingOnRaw` is: decoding it straight to `Date` throws under the
        /// client's timestamp-with-time-zone strategy, and a throw here fails the whole row — so
        /// the offer would simply never appear, with nothing on screen to explain why.
        var missedDateRaw: String?
        /// Optional for the same reason `missedDateRaw` is a string: a synthesised `Decodable`
        /// ignores default values, so declaring this as a plain `Bool = false` made the key
        /// *required* — and a server that had not yet been redeployed would fail to decode the
        /// whole row, taking the repair offer off the screen entirely with nothing to explain why.
        /// Caught by `StreakRepairTests`, whose fixtures are exactly that older payload.
        var monthlyFreezeAvailableRaw: Bool?

        /// Whether the couple's included monthly repair is still unspent. False for anyone not on
        /// Premium, and false against a server that does not know about it yet — so the screen
        /// offers the paid route rather than a button that would refuse.
        var monthlyFreezeAvailable: Bool { monthlyFreezeAvailableRaw ?? false }

        var missedDate: Date? {
            missedDateRaw.flatMap { BackendService.dateOnlyFormatter.date(from: $0) }
        }

        enum CodingKeys: String, CodingKey {
            case repairable
            case streakAtRisk = "streak_at_risk"
            case credits
            case missedDateRaw = "missed_date"
            case monthlyFreezeAvailableRaw = "monthly_freeze_available"
        }
    }

    static func streakRepairState() async throws -> StreakRepairState? {
        let rows: [StreakRepairState] = try await supabase
            .rpc("streak_repair_state")
            .execute()
            .value
        return rows.first
    }

    /// What a repair attempt did.
    enum StreakRepairOutcome {
        case repaired(streak: Int)
        /// Paid for, but the purchase has not reached us yet — RevenueCat's webhook is what grants
        /// the credit, and it is asynchronous. Worth retrying rather than reporting.
        case noCredit
        case refused(String)
    }

    static func repairCoupleStreak() async throws -> StreakRepairOutcome {
        struct Row: Decodable {
            var repaired: Bool
            var currentStreak: Int
            var errorMessage: String?

            enum CodingKeys: String, CodingKey {
                case repaired
                case currentStreak = "current_streak"
                case errorMessage = "error_message"
            }
        }
        let rows: [Row] = try await supabase.rpc("repair_couple_streak").execute().value
        guard let row = rows.first else { return .refused("Couldn't repair that. Try again.") }
        if row.repaired { return .repaired(streak: row.currentStreak) }
        // The one message the server sends as a token rather than as prose, because the app acts
        // on it instead of showing it.
        if row.errorMessage == "no_credit" { return .noCredit }
        return .refused(row.errorMessage ?? "Couldn't repair that. Try again.")
    }

    /// Spends the couple's included monthly repair.
    ///
    /// A separate call from `repairCoupleStreak` because it spends a different thing — one included
    /// rather than one bought. The server grants and consumes the credit in a single transaction,
    /// so a repair it refuses costs the couple nothing.
    static func repairStreakWithMonthlyFreeze() async throws -> StreakRepairOutcome {
        struct Row: Decodable {
            var repaired: Bool
            var currentStreak: Int
            var errorMessage: String?

            enum CodingKeys: String, CodingKey {
                case repaired
                case currentStreak = "current_streak"
                case errorMessage = "error_message"
            }
        }
        let rows: [Row] = try await supabase.rpc("repair_streak_with_monthly_freeze").execute().value
        guard let row = rows.first else { return .refused("Couldn't repair that. Try again.") }
        if row.repaired { return .repaired(streak: row.currentStreak) }

        // Two tokens the app acts on rather than shows. `freeze_used` means this month's is gone —
        // which is a real answer, not a failure — and `premium_required` means the client thought
        // they were Premium and the server disagreed.
        switch row.errorMessage {
        case "freeze_used": return .refused("You've already used this month's repair.")
        case "premium_required": return .refused("A monthly repair is part of Twofold Premium.")
        default: return .refused(row.errorMessage ?? "Couldn't repair that. Try again.")
        }
    }

    // MARK: - Games

    private nonisolated struct GameSessionRow: Decodable {
        var id: UUID
        var coupleId: UUID?
        var gameType: GameType
        var initiatorId: UUID
        var status: GameSessionStatus
        var totalRounds: Int
        var isDaily: Bool
        var deckId: UUID?
        var startedAt: Date?
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, status
            case coupleId = "couple_id"
            case gameType = "game_type"
            case initiatorId = "initiator_id"
            case totalRounds = "total_rounds"
            case isDaily = "is_daily"
            case deckId = "deck_id"
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        func toModel() -> GameSession {
            GameSession(
                id: id, coupleID: coupleId, gameType: gameType, initiatorID: initiatorId, status: status,
                totalRounds: totalRounds, isDaily: isDaily, deckID: deckId, startedAt: startedAt, completedAt: completedAt,
                createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    struct GameSessionRoundRow: Decodable {
        var id: UUID
        var sessionId: UUID
        var roundNumber: Int
        var contentId: UUID
        var discussionStatus: DiscussionRoundStatus?
        var difficulty: SudokuDifficulty?
        var theme: WordSearchTheme?

        enum CodingKeys: String, CodingKey {
            case id, difficulty, theme
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case contentId = "content_id"
            case discussionStatus = "discussion_status"
        }

        func toModel() -> GameSessionRound {
            GameSessionRound(id: id, sessionID: sessionId, roundNumber: roundNumber, contentID: contentId, discussionStatus: discussionStatus, difficulty: difficulty, theme: theme)
        }
    }

    struct GameResponseRow: Decodable {
        var id: UUID
        var sessionId: UUID
        var roundNumber: Int
        var responderId: UUID
        var answer: GameAnswerPayload
        var isCorrect: Bool?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, answer
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case responderId = "responder_id"
            case isCorrect = "is_correct"
            case createdAt = "created_at"
        }

        func toModel() -> GameResponse {
            GameResponse(id: id, sessionID: sessionId, roundNumber: roundNumber, responderID: responderId, answerValue: answer.value, isCorrect: isCorrect, createdAt: createdAt)
        }
    }

    private struct GameResponseInsert: Encodable {
        var sessionId: UUID
        var roundNumber: Int
        var responderId: UUID
        var answer: GameAnswerPayload
        var isCorrect: Bool?

        enum CodingKeys: String, CodingKey {
            case answer
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case responderId = "responder_id"
            case isCorrect = "is_correct"
        }
    }

    private struct TriviaQuestionRow: Decodable {
        var id: UUID
        var category: String
        var question: String
        var options: [String]
        var correctAnswer: String
        var explanation: String?
        var difficulty: String?
        var active: Bool
        var tier: String

        enum CodingKeys: String, CodingKey {
            case id, category, question, options, explanation, difficulty, active, tier
            case correctAnswer = "correct_answer"
        }

        func toModel() -> TriviaQuestion {
            TriviaQuestion(id: id, category: category, question: question, options: options, correctAnswer: correctAnswer, explanation: explanation, difficulty: difficulty, active: active, tier: tier)
        }
    }

    private struct MoreLikelyPromptRow: Decodable {
        var id: UUID
        var prompt: String
        var active: Bool
        var category: String
        var tier: String

        func toModel() -> MoreLikelyPrompt { MoreLikelyPrompt(id: id, prompt: prompt, active: active, category: category, tier: tier) }
    }

    private struct ThisOrThatPromptRow: Decodable {
        var id: UUID
        var optionA: String
        var optionB: String
        var active: Bool
        var category: String
        var tier: String

        enum CodingKeys: String, CodingKey {
            case id, active, category, tier
            case optionA = "option_a"
            case optionB = "option_b"
        }

        func toModel() -> ThisOrThatPrompt { ThisOrThatPrompt(id: id, optionA: optionA, optionB: optionB, active: active, category: category, tier: tier) }
    }

    private struct DeepConversationTopicRow: Decodable {
        var id: UUID
        var topic: String
        var active: Bool
        var category: String
        var tier: String

        func toModel() -> DeepConversationTopic { DeepConversationTopic(id: id, topic: topic, active: active, category: category, tier: tier) }
    }

    /// One row of the daily question bank.
    ///
    /// Mapped onto `DeepConversationTopic` rather than given a model of its own: to everything above
    /// this line a daily question *is* a deep-conversation prompt, and the whole app already knows
    /// how to render one. The table is separate so the two pools stop consuming each other, which is
    /// a content-supply concern and not a reason for a second shape on screen.
    ///
    /// No tier — that is the point of the table. `.plus` is what the model wants for "available to
    /// everyone", since it is the tier every subscriber has.
    private struct DailyQuestionRow: Decodable {
        var id: UUID
        var question: String
        var active: Bool
        var category: String?

        func toModel() -> DeepConversationTopic {
            DeepConversationTopic(id: id, topic: question, active: active, category: category ?? "", tier: "plus")
        }
    }

    struct GameSessionDetail {
        var session: GameSession
        var rounds: [GameSessionRound]
        /// Keyed by `game_session_rounds.content_id`, resolved against whichever content table
        /// matches the session's game type.
        var content: [UUID: GameRoundContent]
        /// Whatever's currently visible to the caller — their own responses always; their
        /// partner's only once both have answered the same round (enforced by RLS, not by
        /// this client filtering anything out).
        var responses: [GameResponse]
    }

    /// A list of rows that each name a `GameType`, minus the rows naming one this build has never
    /// heard of.
    ///
    /// `GameType` is a closed enum and games are added on the server regularly. Decoded as a plain
    /// array, one row of a new type failed the whole list: once a partner on a newer build started
    /// a game this build does not have, this one's history and open games went empty, and its deck
    /// list fell back to the bundled catalogue without saying why. An older build cannot play a
    /// game it does not have, so leaving the row out is the right answer, the one
    /// `GameContentStore.decks()` already gives.
    ///
    /// Only that is forgiven. A row of a known type that fails to decode is still an error, so a
    /// real schema mistake shows up as one rather than as an empty screen.
    struct KnownGameTypes<Element: Decodable>: Decodable {
        var elements: [Element]

        private struct GameTypeProbe: Decodable {
            let gameType: String
            enum CodingKeys: String, CodingKey { case gameType = "game_type" }
        }

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var elements: [Element] = []
            while !container.isAtEnd {
                do {
                    elements.append(try container.decode(Element.self))
                } catch {
                    // A failed decode leaves the container on the same element, so the probe reads
                    // the row that just failed — and moves past it.
                    guard let probe = try? container.decode(GameTypeProbe.self),
                          GameType(rawValue: probe.gameType) == nil
                    else { throw error }
                }
            }
            self.elements = elements
        }
    }

    nonisolated struct GameDeckRow: Decodable {
        var id: UUID
        var topic: String
        var gameType: GameType
        var title: String
        var emoji: String
        var tier: String
        var sortOrder: Int
        var questionCount: Int
        /// Optional so a payload from before 20261113000900 still decodes.
        var adult: Bool?

        enum CodingKeys: String, CodingKey {
            case id, topic, title, emoji, tier, adult
            case gameType = "game_type"
            case sortOrder = "sort_order"
            case questionCount = "question_count"
        }

        @MainActor func toModel() -> GameDeck {
            GameDeck(id: id, topic: topic, gameType: gameType, title: title, emoji: emoji, tier: tier, sortOrder: sortOrder, questionCount: questionCount, isAdult: adult ?? false)
        }
    }

    /// Every active deck across all topics — small enough (a few dozen rows) to fetch in full and
    /// let the caller filter/group client-side, same approach as `fetchGameContentCatalog`.
    static func fetchGameDecks() async throws -> [GameDeck] {
        let rows: KnownGameTypes<GameDeckRow> = try await supabase
            .from("game_decks")
            .select()
            .eq("active", value: true)
            .order("sort_order")
            .execute()
            .value
        return rows.elements.map { $0.toModel() }
    }

    /// The whole deck catalogue and every round behind it, encoded as the payload
    /// `GameContentStore` caches — see that file for why games need a local copy at all, and
    /// `scripts/export-game-content.py`, which produces the bundled seed in this same shape.
    ///
    /// Returned as raw JSON rather than models on purpose: it is written straight to disk, and
    /// decoding it here only to re-encode it would be two chances to drop a column for no gain.
    /// ~2,000 rows and about half a megabyte, so it's fetched on a schedule, not per foreground.
    static func fetchGameContentPayload() async throws -> Data {
        // Paged explicitly. PostgREST caps a plain select at 1,000 rows and says nothing when it
        // truncates — it just returns a short list. The largest content table is around 600 rows
        // today, so a single request happens to be enough, which is exactly how this would ship
        // broken later: content grows, a table crosses the cap, and the catalogue silently loses
        // whatever fell off the end. `GameContentStore.store` only rejects an empty deck list, so a
        // truncated fetch would overwrite a complete cache with a partial one.
        //
        // `scripts/export-game-content.py` already pages for the same reason; this is the half that
        // was missed.
        @Sendable func rows(_ table: String, _ columns: String) async throws -> [[String: AnyJSON]] {
            let pageSize = 1000
            var all: [[String: AnyJSON]] = []
            while true {
                let page: [[String: AnyJSON]] = try await supabase
                    .from(table)
                    .select(columns)
                    .eq("active", value: true)
                    .order("id", ascending: true)
                    .range(from: all.count, to: all.count + pageSize - 1)
                    .execute()
                    .value
                all.append(contentsOf: page)
                if page.count < pageSize { return all }
            }
        }
        // Keyed by `GameType.rawValue`, which is what the store looks them up by.
        async let trivia = rows("trivia_questions", "id,deck_id,question,options,correct_answer,explanation,difficulty,category,tier")
        async let moreLikely = rows("more_likely_prompts", "id,deck_id,prompt,category,tier")
        async let thisOrThat = rows("this_or_that_prompts", "id,deck_id,option_a,option_b,category,tier")
        async let deep = rows("deep_conversation_topics", "id,deck_id,topic,category,tier")
        async let decks = rows("game_decks", "id,topic,game_type,title,emoji,tier,sort_order,question_count,adult")

        let payload: [String: AnyJSON] = [
            "version": .integer(1),
            "decks": .array(try await decks.map { .object($0) }),
            "content": .object([
                GameType.triviaBattle.rawValue: .array(try await trivia.map { .object($0) }),
                GameType.moreLikely.rawValue: .array(try await moreLikely.map { .object($0) }),
                GameType.thisOrThat.rawValue: .array(try await thisOrThat.map { .object($0) }),
                GameType.deepConversations.rawValue: .array(try await deep.map { .object($0) }),
            ]),
        ]
        return try JSONEncoder().encode(AnyJSON.object(payload))
    }

    static func startDeckSession(deckID: UUID) async throws -> UUID {
        struct Params: Encodable {
            var pDeckId: UUID
            enum CodingKeys: String, CodingKey { case pDeckId = "p_deck_id" }
        }
        let id: UUID = try await supabase
            .rpc("start_deck_session", params: Params(pDeckId: deckID))
            .execute()
            .value
        Analytics.capture(Analytics.Event.sessionStart, properties: ["deck_id": deckID.uuidString, "is_deck": true])
        return id
    }

    /// Where each partner stands on 18+ questions. Only whether the partner has opted in, never
    /// when — `adult_content_status` doesn't hand that out.
    struct AdultContentStatus: Decodable, Equatable {
        var me: Bool
        var partner: Bool
        var hasPartner: Bool
        enum CodingKeys: String, CodingKey { case me, partner, hasPartner = "has_partner" }

        /// The decks only exist once both have opted in — the server's rule, mirrored for display.
        var isUnlocked: Bool { me && partner && hasPartner }
    }

    static func fetchAdultContentStatus() async throws -> AdultContentStatus {
        let rows: [AdultContentStatus] = try await supabase
            .rpc("adult_content_status")
            .execute()
            .value
        return rows.first ?? AdultContentStatus(me: false, partner: false, hasPartner: false)
    }

    /// Turning it on is also this person's statement that they're 18 or over: Twofold stores no
    /// age, so the opt-in is the age check. Written only through this RPC; the column itself is
    /// closed to clients.
    static func setAdultContentOptIn(_ isOn: Bool) async throws {
        struct Params: Encodable {
            var pOn: Bool
            enum CodingKeys: String, CodingKey { case pOn = "p_on" }
        }
        try await supabase
            .rpc("set_adult_content_opt_in", params: Params(pOn: isOn))
            .execute()
    }

    // MARK: - Games already on

    /// One unfinished generated or board game, for the top of the Games hub.
    ///
    /// `isMyTurn` means two different things depending on the game, and both are the actionable
    /// reading: on a board it is whose move it is, and on a puzzle it is whether *you* have still
    /// to play it. See `list_open_puzzle_games`.
    nonisolated struct OpenGame: Identifiable, Decodable {
        let id: UUID
        let gameType: GameType
        /// The difficulty or theme, where the game has one.
        let label: String?
        let isMyTurn: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case label
            case id = "session_id"
            case gameType = "game_type"
            case isMyTurn = "is_my_turn"
            case updatedAt = "updated_at"
        }
    }

    /// Best-effort: the hub shows this section or it does not, and a failure here must not take the
    /// rest of the screen with it.
    static func fetchOpenGames() async -> [OpenGame] {
        guard currentUserID != nil else { return [] }
        do {
            let games: KnownGameTypes<OpenGame> = try await supabase.rpc("list_open_puzzle_games").execute().value
            return games.elements
        } catch {
            return []
        }
    }

    /// The running record for the four games that keep one server-side.
    ///
    /// A query rather than a download: Connect 4 keeps its results in
    /// `game_sessions.outcome`, and Word Guess's and Word Search's are inside response payloads, so
    /// aggregating on the device would mean fetching every response either of them has ever
    /// written to draw one line of text.
    ///
    /// Best-effort: the card appears or it does not, and a failure must not take the screen with it.
    static func fetchGameRecords() async -> [GameRecord] {
        guard currentUserID != nil else { return [] }
        do {
            let records: KnownGameTypes<GameRecord> = try await supabase.rpc("get_game_stats").execute().value
            return records.elements
        } catch {
            return []
        }
    }

    static func abandonGameSession(id: UUID) async throws {
        struct Params: Encodable {
            var pSessionId: UUID
            enum CodingKeys: String, CodingKey { case pSessionId = "p_session_id" }
        }
        try await supabase.rpc("abandon_game_session", params: Params(pSessionId: id)).execute()
    }

    /// Returns today's Daily Activity session id, creating it server-side on first call each day
    /// — see `get_daily_question_session` (an ordinary 1-round `deep_conversations`
    /// session flagged `is_daily`, so it plays through the exact same `GameSessionStore` flow as
    /// any other game).
    /// Named for the RPC rather than for the feature: `DailyQuestionRow` is already taken, by a row
    /// of the `daily_questions` bank itself. This is one day's assigned question plus its state.
    private struct DailyQuestionSessionRow: Decodable {
        var sessionId: UUID
        var question: String
        var myAnswered: Bool
        var partnerAnswered: Bool

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case question
            case myAnswered = "my_answered"
            case partnerAnswered = "partner_answered"
        }
    }

    /// Today's question, whole, in one round trip.
    ///
    /// Replaces a chain of three: the session id, then `fetchGameSession(id:)` for the text, then the
    /// answered flags. Five sequential round trips for one sentence, because the middle one is the
    /// generic detail loader and issues four queries of its own. It is right for a ten-round deck
    /// session and wrong for a daily one, which has exactly one round and one question — see
    /// migration 20261110001700.
    ///
    /// The wrappers for the two RPCs this supersedes are gone, having no callers left.
    /// `get_daily_question_session` and `get_daily_question_status` both remain on the server,
    /// because builds already on phones call them and cannot be recalled.
    static func fetchDailyQuestion() async throws -> (sessionID: UUID, question: String, mine: Bool, partner: Bool)? {
        let rows: [DailyQuestionSessionRow] = try await supabase.rpc("get_daily_question").execute().value
        guard let row = rows.first else { return nil }
        return (row.sessionId, row.question, row.myAnswered, row.partnerAnswered)
    }

    /// The partner's answer to today's question, for the Daily question widget. Nil until you have
    /// both answered: RLS keeps a session's responses hidden until it is complete, so this cannot
    /// return an answer early even if asked.
    static func fetchPartnerDailyAnswer(sessionID: UUID, partnerID: UUID) async throws -> String? {
        let rows: [GameResponseRow] = try await supabase
            .from("game_responses")
            .select()
            .eq("session_id", value: sessionID.uuidString)
            .eq("responder_id", value: partnerID.uuidString)
            .limit(1)
            .execute()
            .value
        let answer = rows.first?.toModel().answerValue
        return answer?.isEmpty == false ? answer : nil
    }

    private struct DailyStreakRow: Decodable {
        var currentStreak: Int
        var longestStreak: Int
        /// When the couple's day actually rolls over — real local midnight, computed server-side
        /// (see `get_daily_streak`). The card's countdown reads this rather than re-deriving it,
        /// since for a couple it depends on *both* partners' timezones.
        var nextBoundary: Date?

        enum CodingKeys: String, CodingKey {
            case currentStreak = "current_streak"
            case longestStreak = "longest_streak"
            case nextBoundary = "next_boundary"
        }
    }

    /// No row yet means the couple hasn't answered a daily question at all — a streak of 0,
    /// not an error.
    ///
    /// Goes through `get_daily_streak()` rather than selecting `daily_streaks` directly: the
    /// stored `current_streak` is only ever recomputed when someone *answers*, so a couple who
    /// last answered days ago still has their old number sitting in the column. Reading it raw
    /// (what this used to do) displayed a streak that had actually already lapsed. The RPC
    /// applies the same "still alive" rule the increment side uses — see its own comment.
    static func fetchDailyStreak() async throws -> (current: Int, longest: Int, resetsAt: Date?) {
        let rows: [DailyStreakRow] = try await supabase.rpc("get_daily_streak").execute().value
        guard let row = rows.first else { return (0, 0, nil) }
        return (row.currentStreak, row.longestStreak, row.nextBoundary)
    }

    private struct DeckProgressRow: Decodable {
        var deckId: UUID
        var sessionId: UUID
        var status: GameSessionStatus
        var totalRounds: Int
        var myAnswered: Int
        var partnerAnswered: Int
        var completedAt: Date?

        enum CodingKeys: String, CodingKey {
            case deckId = "deck_id"
            case sessionId = "session_id"
            case status
            case totalRounds = "total_rounds"
            case myAnswered = "my_answered"
            case partnerAnswered = "partner_answered"
            case completedAt = "completed_at"
        }
    }

    /// One row per non-abandoned/archived deck session for the caller's couple — keyed by deck id
    /// client-side (a deck only ever has one live session at a time: resetting abandons the old
    /// one before starting a new one).
    static func fetchDeckProgress() async throws -> [UUID: DeckProgress] {
        let rows: [DeckProgressRow] = try await supabase.rpc("get_deck_progress").execute().value
        var result: [UUID: DeckProgress] = [:]
        for row in rows {
            result[row.deckId] = DeckProgress(
                sessionID: row.sessionId, status: row.status, totalRounds: row.totalRounds,
                myAnswered: row.myAnswered, partnerAnswered: row.partnerAnswered, completedAt: row.completedAt
            )
        }
        return result
    }

    /// Relies on RLS to scope results to the caller's own couple — no couple id is passed or
    /// needed client-side.
    ///
    /// `limit` is not optional-by-accident: this query had no bound at all, which meant it was
    /// really bounded by PostgREST's `max_rows` (1000, see supabase/config.toml) and would have
    /// started silently dropping rows there with no signal to the client. The daily question alone
    /// produces a session per day, so that ceiling is reachable. An explicit limit makes the cut-off
    /// deliberate and, because the sort is newest-first, keeps the rows anyone actually wants.
    /// Callers that need to know whether they hit it can compare `count` against what they asked
    /// for — one more than the cap is the usual trick, which `GameHistoryView` uses.
    /// `offset` pages through the list rather than pulling the whole history at once. Game History
    /// used to fetch every completed session up front — one a day from the daily question alone —
    /// and then fetch full detail for most of them, so the screen got slower every month a couple
    /// used the app.
    ///
    /// Ordered by `updated_at` for stable paging: the column is always populated, whereas
    /// `completed_at` isn't on older rows, and a null in the sort key makes page boundaries
    /// unstable. The caller re-sorts a page by true completion date for display.
    static func fetchGameSessions(status: GameSessionStatus? = nil, limit: Int = 200, offset: Int = 0) async throws -> [GameSession] {
        var query = supabase.from("game_sessions").select()
        if let status {
            query = query.eq("status", value: status.rawValue)
        }
        let rows: KnownGameTypes<GameSessionRow> = try await query
            .order("updated_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        return rows.elements.map { $0.toModel() }
    }

    static func fetchGameSession(id: UUID) async throws -> GameSessionDetail {
        let sessionRow: GameSessionRow = try await supabase
            .from("game_sessions")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        let session = sessionRow.toModel()

        let roundRows: [GameSessionRoundRow] = try await supabase
            .from("game_session_rounds")
            .select()
            .eq("session_id", value: id)
            .order("round_number")
            .execute()
            .value
        let rounds = roundRows.map { $0.toModel() }

        let responseRows: [GameResponseRow] = try await supabase
            .from("game_responses")
            .select()
            .eq("session_id", value: id)
            .execute()
            .value
        let responses = responseRows.map { $0.toModel() }

        // `isDaily` as well as the type: a daily session is a `deep_conversations` session whose
        // content lives in its own table now, and the type alone cannot tell the two apart.
        let content = try await resolveContent(
            gameType: session.gameType,
            isDaily: session.isDaily,
            contentIDs: rounds.map(\.contentID)
        )

        return GameSessionDetail(session: session, rounds: rounds, content: content, responses: responses)
    }

    private static func resolveContent(gameType: GameType, isDaily: Bool = false, contentIDs: [UUID]) async throws -> [UUID: GameRoundContent] {
        let unique = Array(Set(contentIDs))
        guard !unique.isEmpty else { return [:] }
        switch gameType {
        // Nothing to resolve. These `content_id`s are not keys into anything — they *are* the
        // puzzle, generated from those 128 bits on each device, so there is no row to go and get.
        // For Word Guess that is also what keeps the answer off the server entirely.
        case .sudoku, .wordGuess, .wordSearch, .connectFour:
            return [:]
        case .triviaBattle:
            let rows: [TriviaQuestionRow] = try await supabase.from("trivia_questions").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.trivia($0.toModel())) })
        case .moreLikely:
            let rows: [MoreLikelyPromptRow] = try await supabase.from("more_likely_prompts").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.moreLikely($0.toModel())) })
        case .thisOrThat:
            let rows: [ThisOrThatPromptRow] = try await supabase.from("this_or_that_prompts").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.thisOrThat($0.toModel())) })
        case .deepConversations:
            // The daily question draws from its own bank (20261102000000), so a daily session's
            // content id is not a `deep_conversation_topics` id and looking for it there finds
            // nothing — which renders as a session with no question rather than an error.
            if isDaily {
                let rows: [DailyQuestionRow] = try await supabase.from("daily_questions").select().in("id", values: unique).execute().value
                return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.deepConversation($0.toModel())) })
            }
            let rows: [DeepConversationTopicRow] = try await supabase.from("deep_conversation_topics").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.deepConversation($0.toModel())) })
        }
    }

    /// Upsert, not a plain insert — lets the back button (`GameSessionStore.goBack`) resubmit an
    /// already-answered round to change it, which resolves to an UPDATE on the existing
    /// `(session_id, round_number, responder_id)` row rather than a duplicate-key failure. See
    /// `game_responses_update_own_active` (RLS) for the policy that permits that UPDATE path —
    /// `advance_game_session`'s trigger only fires on INSERT, so re-editing an already-counted
    /// round never double-counts it.
    static func submitGameResponse(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool? = nil) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("game_responses")
            .upsert(
                GameResponseInsert(
                    sessionId: sessionID,
                    roundNumber: roundNumber,
                    responderId: userID,
                    answer: GameAnswerPayload(value: answerValue),
                    isCorrect: isCorrect
                ),
                onConflict: "session_id,round_number,responder_id"
            )
            .execute()
    }

    /// Unlike `subscribeToFlightStatusEvents`, this stream deliberately carries no payload —
    /// per the reveal design, the client always re-fetches via the RLS-protected select on any
    /// change rather than trusting realtime payload contents for sensitive round data.
    static func subscribeToGameSession(id: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        signalStream(channelName: "game_session_\(id.uuidString)", changes: [
            .insert("game_responses", filter: .eq("session_id", value: id.uuidString)),
            .update("game_sessions", filter: .eq("id", value: id.uuidString)),
        ])
    }
}
