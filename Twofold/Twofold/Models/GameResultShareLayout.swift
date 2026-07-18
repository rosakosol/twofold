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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scoreSnapshot: "chart.bar.fill"
        case .dailyStreak: "flame.fill"
        case .namesAndAnswer: "text.bubble.fill"
        }
    }

    var label: String {
        switch self {
        case .scoreSnapshot: "Snapshot"
        case .dailyStreak: "Streak"
        case .namesAndAnswer: "Simple"
        }
    }
}
