//
//  GameResultShareLayout.swift
//  Twofold
//

import Foundation

/// Which visual "render" of a game result the share card picker is showing —
/// see `GameResultShareData.availableLayouts` for which cases apply to a given result.
enum GameResultShareLayout: String, CaseIterable, Identifiable {
    case scoreSnapshot
    case dailyStreak
    case namesAndAnswer
    /// The two answers alone, as a real tailed chat exchange (`SpeechBubbleShape`) with almost
    /// no other chrome — an isolated-component sticker rather than a fully composed card, for
    /// swiping to when you just want the exchange itself, not a headline/score around it.
    case speechBubble

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scoreSnapshot: "chart.bar.fill"
        case .dailyStreak: "flame.fill"
        case .namesAndAnswer: "text.bubble.fill"
        case .speechBubble: "bubble.left.and.bubble.right.fill"
        }
    }

    var label: String {
        switch self {
        case .scoreSnapshot: "Snapshot"
        case .dailyStreak: "Streak"
        case .namesAndAnswer: "Simple"
        case .speechBubble: "Bubble"
        }
    }
}
