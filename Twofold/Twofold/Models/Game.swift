//
//  Game.swift
//  Twofold
//

import SwiftUI

enum GameCategory: String, CaseIterable, Hashable {
    case compete = "Compete"
    case connect = "Connect"
}

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
    var displayName: String { rawValue }

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

    var color: Color {
        switch self {
        case .starters: .purple
        case .getToKnowEachOther: Theme.skyBlue
        case .relationship: Theme.heartRed
        case .travel: Theme.leafGreen
        case .foodAndCulture: .orange
        case .family: .brown
        case .moneyAndFinances: .teal
        case .moralValues: .yellow
        case .hobbiesAndLifestyle: .pink
        case .history: .gray
        case .edgyQuestions: .red
        }
    }
}

enum GameType: String, Codable, CaseIterable, Hashable, Identifiable {
    case triviaBattle = "trivia_battle"
    case moreLikely = "more_likely"
    case thisOrThat = "this_or_that"
    case deepConversations = "deep_conversations"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .triviaBattle: "Trivia Battle"
        case .moreLikely: "Who's More Likely To"
        case .thisOrThat: "This or That"
        case .deepConversations: "Deep Conversation"
        }
    }

    /// Compact uppercase label for deck badges (e.g. topic detail cards) — `displayName` reads
    /// naturally as a game-type title, but is too long for a small pill.
    var shortLabel: String {
        switch self {
        case .triviaBattle: "TRIVIA"
        case .moreLikely: "MORE LIKELY"
        case .thisOrThat: "THIS OR THAT"
        case .deepConversations: "DEEP CONVERSATION"
        }
    }

    var tagline: String {
        switch self {
        case .triviaBattle: "Put your knowledge to the test."
        case .moreLikely: "Who knows your relationship best?"
        case .thisOrThat: "Choose, reveal, and see where you match."
        case .deepConversations: "Talk through the things that matter, together."
        }
    }

    var category: GameCategory {
        switch self {
        case .triviaBattle, .moreLikely: .compete
        case .thisOrThat, .deepConversations: .connect
        }
    }

    var durationMinutes: Int {
        switch self {
        case .triviaBattle: 12
        case .moreLikely: 8
        case .thisOrThat: 6
        case .deepConversations: 15
        }
    }

    var durationLabel: String { "\(durationMinutes) min" }

    var icon: String {
        switch self {
        case .triviaBattle: "questionmark.circle.fill"
        case .moreLikely: "person.2.wave.2.fill"
        case .thisOrThat: "arrow.left.arrow.right.circle.fill"
        case .deepConversations: "bubble.left.and.bubble.right.fill"
        }
    }

    var iconGradient: [Color] {
        switch self {
        case .triviaBattle: [Theme.skyBlue, Theme.leafGreen]
        case .moreLikely: [Theme.heartRed, .orange]
        case .thisOrThat: [.purple, Theme.skyBlue]
        case .deepConversations: [Theme.leafGreen, Theme.skyBlue]
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
    var coupleID: UUID
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
struct DeckProgress: Hashable {
    var sessionID: UUID
    var status: GameSessionStatus
    var totalRounds: Int
    var myAnswered: Int
    var partnerAnswered: Int

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
