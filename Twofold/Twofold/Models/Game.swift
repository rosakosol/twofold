//
//  Game.swift
//  Twofold
//

import SwiftUI

/// Cross-game content grouping, independent of `GameType` — a single topic (e.g. "Travel") spans
/// content rows across all 4 content tables, powering the Games hub's topic-browsing section.
/// Backed by each content table's `category` column (a plain string, not a DB enum, so a
/// mismatched value never fails to decode — see `TriviaQuestion.category` etc.); `GameTopic(rawValue:)`
/// is only used to resolve display metadata (icon/color) for a known category string.
enum GameTopic: String, CaseIterable, Hashable, Identifiable {
    case starters = "Starters"
    case getToKnowEachOther = "Get to Know Each Other"
    case relationship = "Relationship"
    case travel = "Travel"
    case foodAndCulture = "Food & Culture"
    case family = "Family"
    case moneyAndFinances = "Money & Finances"
    case moralValues = "Moral Values"
    case hobbiesAndLifestyle = "Hobbies & Lifestyle"
    case history = "History"
    case edgyQuestions = "Edgy Questions"

    var id: String { rawValue }

    /// Sentence case for display. `rawValue` stays as the database writes it, since that is what
    /// content rows are matched on.
    var displayName: String {
        switch self {
        case .starters: "Starters"
        case .getToKnowEachOther: "Get to know each other"
        case .relationship: "Relationship"
        case .travel: "Travel"
        case .foodAndCulture: "Food & culture"
        case .family: "Family"
        case .moneyAndFinances: "Money & finances"
        case .moralValues: "Moral values"
        case .hobbiesAndLifestyle: "Hobbies & lifestyle"
        case .history: "History"
        case .edgyQuestions: "Edgy questions"
        }
    }

    var icon: String {
        switch self {
        case .starters: "sparkles"
        case .getToKnowEachOther: "person.2.fill"
        case .relationship: "heart.fill"
        case .travel: "airplane"
        case .foodAndCulture: "fork.knife"
        case .family: "house.fill"
        case .moneyAndFinances: "dollarsign.circle.fill"
        case .moralValues: "hands.sparkles.fill"
        case .hobbiesAndLifestyle: "figure.run"
        case .history: "building.columns.fill"
        case .edgyQuestions: "flame.fill"
        }
    }

    /// The topic's colour. Every topic takes one of the four brand hues (spec section 2.5: no
    /// teal, purple or orange anywhere in games), grouped by what the topic is about: coral for
    /// the two of you, green for the world outside, blue and indigo for everything else. History
    /// stays neutral. These are the text-safe tones, so the same colour works as an icon, a tint
    /// and a word.
    var color: Color {
        switch self {
        case .starters: Theme.indigo
        case .getToKnowEachOther: Theme.accent
        case .relationship: Theme.coral
        case .travel: Theme.success
        case .foodAndCulture: Theme.success
        case .family: Theme.coral
        case .moneyAndFinances: Theme.accent
        case .moralValues: Theme.indigo
        case .hobbiesAndLifestyle: Theme.success
        case .history: Theme.textSecondary
        case .edgyQuestions: Theme.coral
        }
    }

    /// The colour for the topic's name as text. The same as `color`: each brand hue's adaptive
    /// token already clears 4.5:1 on cards in both appearances.
    var textColor: Color { color }
}

enum GameType: String, Codable, CaseIterable, Hashable, Identifiable {
    case triviaBattle = "trivia_battle"
    case moreLikely = "more_likely"
    case thisOrThat = "this_or_that"
    case deepConversations = "deep_conversations"
    /// The odd ones out, deliberately. Every case above names a bank of prompts; these two name a
    /// puzzle generated on device from the round's id, so they have no content table and
    /// `resolveContent` has nothing to resolve for them.
    case sudoku
    /// Named for what it is rather than after the game it resembles — the mechanic is nobody's
    /// property but the name is somebody's trademark.
    case wordGuess = "word_guess"
    case wordSearch = "word_search"
    /// The first game here whose state is a board rather than a puzzle — see `game_moves`. Also
    /// the only one that cannot be played alone.
    case connectFour = "connect_four"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .triviaBattle: "Trivia battle"
        case .moreLikely: "Who's more likely to"
        case .thisOrThat: "This or that"
        case .deepConversations: "Deep conversation"
        case .sudoku: "Sudoku"
        case .wordGuess: "Word guess"
        case .wordSearch: "Word search"
        case .connectFour: "Connect 4"
        }
    }

    /// Compact label for deck badges (e.g. topic detail cards) — `displayName` reads
    /// naturally as a game-type title, but is too long for a small pill.
    var shortLabel: String {
        switch self {
        case .triviaBattle: "Trivia"
        case .moreLikely: "More likely"
        case .thisOrThat: "This or that"
        case .deepConversations: "Deep conversation"
        case .sudoku: "Sudoku"
        case .wordGuess: "Word guess"
        case .wordSearch: "Word search"
        case .connectFour: "Connect 4"
        }
    }

    var tagline: String {
        switch self {
        case .triviaBattle: "Put your knowledge to the test."
        case .moreLikely: "Who knows your relationship best?"
        case .thisOrThat: "Choose, reveal, and see where you match."
        case .deepConversations: "Talk through the things that matter, together."
        case .sudoku: "The same grid, on both your phones."
        case .wordGuess: "One word, six guesses, both of you."
        case .wordSearch: "Same grid, same words. Fastest finder wins."
        case .connectFour: "One board, taking turns. Four in a row wins."
        }
    }

    /// Only More Likely is unplayable solo — its answer is literally the UUID of *which
    /// partner* is more likely, so the question has no meaning without a second real person.
    /// The other three have an objective answer (Trivia), a private pick with no partner
    /// needed to record it (This or That), or free text (Deep Conversations) — all can be
    /// started and answered solo, with results/comparison unlocking once a partner joins.
    /// `start_deck_session`/`get_daily_question_session` enforce this same rule server-side.
    ///
    /// Connect 4 joins it for a different reason: More Likely's answer is which partner, so the
    /// question has no meaning alone; Connect 4 simply has no opponent. `start_connect_four_session`
    /// enforces this one server-side, which the client check only mirrors.
    var requiresPartner: Bool { self == .moreLikely || self == .connectFour }

    /// Whether this game's content comes from a curated deck.
    ///
    /// The four conversation games draw rounds from a bank and so have a deck list to browse; the
    /// five below generate their own or keep a board, and each has a small entry screen standing in
    /// for one. The Games hub splits on exactly this — a swipeable row of decks reads nothing like
    /// a grid of puzzles, and nine cards in one row buries the last five.
    var hasDecks: Bool {
        switch self {
        case .triviaBattle, .moreLikely, .thisOrThat, .deepConversations: true
        case .sudoku, .wordGuess, .wordSearch, .connectFour: false
        }
    }

    var durationMinutes: Int {
        switch self {
        case .triviaBattle: 12
        case .moreLikely: 8
        case .thisOrThat: 6
        case .deepConversations: 15
        // Wider than the others by nature — an Easy goes in five minutes and an Expert can take
        // an evening. This is the number shown on a card before anyone has chosen a difficulty,
        // so it is the middle of the range rather than a promise.
        case .sudoku: 20
        // Six guesses is the whole game, and most boards end well before that.
        case .wordGuess: 5
        // Eight words in a hundred letters. Quicker than a sudoku, slower than a word.
        case .wordSearch: 8
        // A guess at best: a game played a disc at a time across a day is not 10 minutes of
        // anybody's attention, and there is no honest single number for that.
        case .connectFour: 10
        // As honest as the Connect 4 number, which is to say not very: a game played a move at a
        // time across a week is not 20 minutes of anybody's attention.
        }
    }

    var durationLabel: String { "\(durationMinutes) min" }

    var icon: String {
        switch self {
        case .triviaBattle: "questionmark.circle.fill"
        case .moreLikely: "person.2.wave.2.fill"
        case .thisOrThat: "arrow.left.arrow.right.circle.fill"
        case .deepConversations: "bubble.left.and.bubble.right.fill"
        case .sudoku: "square.grid.3x3.fill"
        case .wordGuess: "textformat.abc"
        case .wordSearch: "square.grid.4x3.fill"
        case .connectFour: "circle.grid.3x3.fill"
        }
    }

    var iconGradient: [Color] {
        switch self {
        // Section 2.5's game colours for the four conversation games, as fixed fills so white
        // icons stay legible in both appearances. Puzzles take one brand hue each.
        case .triviaBattle: [Color(hex: 0x1F8636), Color(hex: 0x16702A)]
        case .moreLikely: [Color(hex: 0xD23A52), Color(hex: 0xB8274A)]
        case .thisOrThat: [Color(hex: 0x1A6FD6), Color(hex: 0x0B5FB0)]
        case .deepConversations: [Color(hex: 0x3A56D9), Color(hex: 0x2B3FB0)]
        case .sudoku: [Theme.indigoFill, Theme.accentFill]
        case .wordGuess: [Theme.successFill, Theme.accentFill]
        case .wordSearch: [Theme.accentFill, Theme.indigoFill]
        case .connectFour: [Theme.coralFill, Theme.accentFill]
        }
    }

    /// The game's colour (docs/TWOFOLD_DESIGN.md, section 2.5). It follows the game everywhere:
    /// its tile, its play card, its results header and its share card. White text on all of them.
    var gradient: LinearGradient { Brand.gradient(gradientStops.from, gradientStops.to) }

    /// The two stops of `gradient`, for anything that needs the colours rather than the gradient
    /// (a share card's canvas).
    var gradientStops: (from: UInt32, to: UInt32) {
        switch self {
        case .deepConversations, .sudoku: (0x3A56D9, 0x2B3FB0)
        case .thisOrThat, .wordSearch: (0x1A6FD6, 0x0B5FB0)
        case .triviaBattle, .wordGuess: (0x1F8636, 0x16702A)
        case .moreLikely, .connectFour: (0xD23A52, 0xB8274A)
        }
    }

    /// The hue behind `gradient`, for the tinted icon chips puzzles use on neutral cards (2.6).
    var baseHue: UInt32 {
        switch self {
        case .deepConversations, .sudoku: 0x3A56D9
        case .thisOrThat, .wordSearch: 0x1A6FD6
        case .triviaBattle, .wordGuess: 0x1F8636
        case .moreLikely, .connectFour: 0xD23A52
        }
    }

    /// A tinted chip behind the game's icon: 26% of the hue over white, 45% over the night colour.
    var chipTint: Color { Brand.tint(baseHue) }

    /// The icon on `chipTint`, in the hue's text-safe tone for each appearance.
    var chipForeground: Color {
        switch baseHue {
        case 0x3A56D9: Brand.triviaShapes[0]
        case 0x1A6FD6: Brand.triviaShapes[1]
        case 0x1F8636: Brand.triviaShapes[2]
        default: Brand.triviaShapes[3]
        }
    }

    var ctaTitle: String {
        switch self {
        case .deepConversations: "Start conversation"
        default: "Play now"
        }
    }
}

enum GameSessionStatus: String, Codable, Hashable {
    case draft, active
    case waitingForPartner = "waiting_for_partner"
    case completed, abandoned, archived
}

struct GameSession: Identifiable, Hashable {
    let id: UUID
    /// Nil for a solo (unpaired) session — see `start_deck_session`/`get_daily_question_session`'s
    /// solo branch. Reattached to a real couple by `respond_to_connection_request` the moment
    /// the session's initiator pairs up.
    var coupleID: UUID?
    var gameType: GameType
    var initiatorID: UUID
    var status: GameSessionStatus
    var totalRounds: Int
    /// True for the couple's single daily Daily-Activity session (an ordinary 1-round
    /// `deep_conversations` session under the hood — see `get_daily_question_session`).
    var isDaily: Bool
    /// Set when this session was started from a curated deck (`start_deck_session`) rather than
    /// the shared pool (`start_game_session`) — nil for every other session.
    var deckID: UUID?
    var startedAt: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

/// A small, curated, individually-playable subset of one game type's content, scoped to one
/// topic — what the topic detail screen actually lists and lets you start, replacing the earlier
/// "just a count over the shared pool" model. `game_decks` is a genuinely separate table from
/// the 4 content tables; a deck's questions are whichever existing rows got tagged with its id
/// via `deck_id` (see the `20260714000000_game_decks.sql` migration).
struct GameDeck: Identifiable, Hashable {
    let id: UUID
    var topic: String
    var gameType: GameType
    var title: String
    var emoji: String
    var tier: String
    var sortOrder: Int
    var questionCount: Int
}

/// Per-partner completion for one deck's session — counts only, never answer content, sourced
/// from `get_deck_progress()` (a SECURITY DEFINER RPC that deliberately bypasses
/// `game_responses`' own "hidden until both partners are done" RLS so an avatar tick can appear
/// the moment *that* partner finishes, independent of the other). See
/// `20260715000000_deck_progress_rpc.sql`.
struct DeckProgress: Hashable, Codable {
    var sessionID: UUID
    var status: GameSessionStatus
    var totalRounds: Int
    var myAnswered: Int
    var partnerAnswered: Int
    /// When both partners finished — `completed_at` if the session's own row has it, else
    /// `updated_at` (same fallback `GameHistoryView.completionDate(for:)` uses for the
    /// equivalent case on the History screen). Only meaningful once `bothCompleted`.
    var completedAt: Date?

    /// Whether anyone has actually answered anything yet. A `DeckProgress` row existing is not
    /// the same thing: opening a deck creates its session (`start_deck_session`) before a single
    /// question is answered, so a deck someone opened and immediately backed out of has progress
    /// with zero answers on both sides.
    var hasAnyAnswers: Bool { myAnswered > 0 || partnerAnswered > 0 }

    /// Finished, as the server sees it. `advance_game_session` sets `completed` once everyone who
    /// needs to answer has — both partners for a couple's session, the initiator alone for a solo
    /// one — so this is the one check that's right in both cases. `bothCompleted` below is derived
    /// purely from answer counts and so never becomes true for a solo player, who has no partner
    /// to supply the other half.
    var isCompleted: Bool { status == .completed }

    var myCompleted: Bool { myAnswered >= totalRounds }
    var partnerCompleted: Bool { partnerAnswered >= totalRounds }
    var bothCompleted: Bool { myCompleted && partnerCompleted }
    var isInProgress: Bool { !bothCompleted && (myAnswered > 0 || partnerAnswered > 0) }
}

/// Where a specific partner is in a session — derived client-side from how many rounds they've
/// answered (`GameSessionStore`), never stored: each partner progresses independently now, so
/// there's no single shared pointer that could represent "where" both people are at once.
enum PartnerProgress: Hashable {
    case notStarted
    case inProgress(answered: Int, total: Int)
    case finished
}

enum DiscussionRoundStatus: String, Codable, Hashable {
    case talkedAbout = "talked_about"
    case comeBackLater = "come_back_later"
}

struct GameSessionRound: Identifiable, Hashable {
    let id: UUID
    var sessionID: UUID
    var roundNumber: Int
    var contentID: UUID
    var discussionStatus: DiscussionRoundStatus?
    /// Sudoku only, and nil for every other game type. Its own column rather than a reuse of
    /// `discussionStatus` above — that one is `text` in Postgres but a closed two-case enum here,
    /// so a round carrying a difficulty in it would fail to decode and take the entire session
    /// fetch with it.
    var difficulty: SudokuDifficulty?
    /// Word Search only, nil for every other game type. Its own column for the same reason
    /// `difficulty` has one — see 20261010000200, which is the migration that learned it.
    var theme: WordSearchTheme?
}

/// `game_responses.answer` is a single-key jsonb payload (`{"value": "..."}`) regardless of
/// game type — every game's answer boils down to one string (a chosen option's text, a
/// "me"/"partner" pick, an option-a/option-b pick, or free-form discussion text), so a richer
/// per-game-type payload shape isn't needed.
struct GameAnswerPayload: Codable, Hashable {
    var value: String
}

struct GameResponse: Identifiable, Hashable {
    let id: UUID
    var sessionID: UUID
    var roundNumber: Int
    var responderID: UUID
    var answerValue: String
    var isCorrect: Bool?
    var createdAt: Date
}

// MARK: - Content

struct TriviaQuestion: Identifiable, Hashable {
    let id: UUID
    var category: String
    var question: String
    var options: [String]
    var correctAnswer: String
    var explanation: String?
    var difficulty: String?
    var active: Bool
    var tier: String
}

struct MoreLikelyPrompt: Identifiable, Hashable {
    let id: UUID
    var prompt: String
    var active: Bool
    var category: String
    var tier: String
}

struct ThisOrThatPrompt: Identifiable, Hashable {
    let id: UUID
    var optionA: String
    var optionB: String
    var active: Bool
    var category: String
    var tier: String
}

struct DeepConversationTopic: Identifiable, Hashable {
    let id: UUID
    var topic: String
    var active: Bool
    var category: String
    var tier: String
}

/// Whichever content type applies, resolved client-side by `GameSessionStore` based on the
/// session's `gameType` — `game_session_rounds.content_id` has no DB foreign key since which
/// table it points into is polymorphic.
enum GameRoundContent: Hashable {
    case trivia(TriviaQuestion)
    case moreLikely(MoreLikelyPrompt)
    case thisOrThat(ThisOrThatPrompt)
    case deepConversation(DeepConversationTopic)
}

// MARK: - Answer value conventions

/// Who's More Likely To stores the **chosen person's user id** (as a string) rather than a
/// relative "me"/"partner" label — the two responders' notions of "me" refer to different
/// people, so a relative label would make `GameLogic.matchCount`'s plain string-equality check
/// wrong (e.g. "me" from partner A and "partner" from partner B can both mean partner A, which
/// is a match, but the strings wouldn't be equal). A shared absolute id makes equality correct.
enum ThisOrThatChoice: String, Hashable {
    case optionA = "option_a"
    case optionB = "option_b"
}
