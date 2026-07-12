//
//  Game.swift
//  Twofold
//

import SwiftUI

enum GameCategory: String, CaseIterable, Hashable {
    case compete = "Compete"
    case connect = "Connect"
}

enum GameType: String, Codable, CaseIterable, Hashable, Identifiable {
    case travelTrivia = "travel_trivia"
    case moreLikely = "more_likely"
    case thisOrThat = "this_or_that"
    case discussBeforeTravelling = "discuss_before_travelling"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .travelTrivia: "Travel Trivia Battle"
        case .moreLikely: "Who's More Likely To"
        case .thisOrThat: "This or That"
        case .discussBeforeTravelling: "Discuss Before Travelling"
        }
    }

    var tagline: String {
        switch self {
        case .travelTrivia: "Put your travel knowledge to the test."
        case .moreLikely: "Who knows your relationship best?"
        case .thisOrThat: "Choose, reveal, and see where you match."
        case .discussBeforeTravelling: "Talk through the things that make trips smoother."
        }
    }

    var category: GameCategory {
        switch self {
        case .travelTrivia, .moreLikely: .compete
        case .thisOrThat, .discussBeforeTravelling: .connect
        }
    }

    var durationMinutes: Int {
        switch self {
        case .travelTrivia: 5
        case .moreLikely: 5
        case .thisOrThat: 3
        case .discussBeforeTravelling: 10
        }
    }

    var durationLabel: String { "\(durationMinutes) min" }

    var icon: String {
        switch self {
        case .travelTrivia: "airplane.circle.fill"
        case .moreLikely: "person.2.wave.2.fill"
        case .thisOrThat: "arrow.left.arrow.right.circle.fill"
        case .discussBeforeTravelling: "bubble.left.and.bubble.right.fill"
        }
    }

    var iconGradient: [Color] {
        switch self {
        case .travelTrivia: [Theme.skyBlue, Theme.leafGreen]
        case .moreLikely: [Theme.heartRed, .orange]
        case .thisOrThat: [.purple, Theme.skyBlue]
        case .discussBeforeTravelling: [Theme.leafGreen, Theme.skyBlue]
        }
    }

    var ctaTitle: String {
        switch self {
        case .discussBeforeTravelling: "Start conversation"
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
    var startedAt: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
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
}

struct MoreLikelyPrompt: Identifiable, Hashable {
    let id: UUID
    var prompt: String
    var active: Bool
}

struct ThisOrThatPrompt: Identifiable, Hashable {
    let id: UUID
    var optionA: String
    var optionB: String
    var active: Bool
}

struct DiscussionTopic: Identifiable, Hashable {
    let id: UUID
    var topic: String
    var active: Bool
}

/// Whichever content type applies, resolved client-side by `GameSessionStore` based on the
/// session's `gameType` — `game_session_rounds.content_id` has no DB foreign key since which
/// table it points into is polymorphic.
enum GameRoundContent: Hashable {
    case trivia(TriviaQuestion)
    case moreLikely(MoreLikelyPrompt)
    case thisOrThat(ThisOrThatPrompt)
    case discuss(DiscussionTopic)
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
