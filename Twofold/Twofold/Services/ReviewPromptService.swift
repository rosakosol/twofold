//
//  ReviewPromptService.swift
//  Twofold
//
//  Tracks which "first" milestones have already prompted for a review, and whether the user has
//  ever responded positively — Apple gives no API to detect an actual App Store review being
//  left, so "until they leave a review" is approximated as "until they say yes" to our own
//  custom ask (ReviewPromptView), which is what actually triggers the system prompt.
//  Per-milestone flags mean each of the five moments only ever prompts once; the positive-opt-in
//  flag means saying yes anywhere stops all future prompting for good. A "not really" response
//  intentionally leaves future milestones free to ask again.
//

import Foundation

enum ReviewMilestone: String, CaseIterable {
    case partnerConnected
    case firstFlight
    case firstTrip
    case firstMemory
    case firstGameResults
}

enum ReviewPromptService {
    private static let hasRatedKey = "reviewPrompt.hasRespondedPositively"

    private static func shownKey(_ milestone: ReviewMilestone) -> String {
        "reviewPrompt.shown.\(milestone.rawValue)"
    }

    static var hasRespondedPositively: Bool {
        UserDefaults.standard.bool(forKey: hasRatedKey)
    }

    static func markRespondedPositively() {
        UserDefaults.standard.set(true, forKey: hasRatedKey)
    }

    /// Marks a milestone as shown and returns whether it's actually eligible to prompt right
    /// now (not already shown for this milestone, and the user hasn't already said yes
    /// elsewhere) — call once per detected milestone; a `false` result means don't show anything.
    static func markShownIfEligible(_ milestone: ReviewMilestone) -> Bool {
        guard !hasRespondedPositively, !UserDefaults.standard.bool(forKey: shownKey(milestone)) else { return false }
        UserDefaults.standard.set(true, forKey: shownKey(milestone))
        return true
    }
}
