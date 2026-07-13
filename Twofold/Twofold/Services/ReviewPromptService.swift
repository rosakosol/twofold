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
//  A global once-per-day cap sits on top of the per-milestone flags — someone brand new to the
//  app can plausibly cross several milestones (connect partner, add a flight, add a trip...) in
//  one sitting, and without this they'd get prompted for a rating up to five times in a single
//  session. A milestone blocked by the daily cap is NOT marked shown — it stays eligible to
//  prompt on a later day instead of being silently used up.
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
    private static let lastShownAtKey = "reviewPrompt.lastShownAt"

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
    /// now (not already shown for this milestone, the user hasn't already said yes elsewhere,
    /// and no prompt has been shown yet today for any milestone) — call once per detected
    /// milestone; a `false` result means don't show anything.
    static func markShownIfEligible(_ milestone: ReviewMilestone) -> Bool {
        guard !hasRespondedPositively, !UserDefaults.standard.bool(forKey: shownKey(milestone)) else { return false }
        if let lastShownAt = UserDefaults.standard.object(forKey: lastShownAtKey) as? Date, Calendar.current.isDateInToday(lastShownAt) {
            return false
        }
        UserDefaults.standard.set(true, forKey: shownKey(milestone))
        UserDefaults.standard.set(Date.now, forKey: lastShownAtKey)
        return true
    }
}
