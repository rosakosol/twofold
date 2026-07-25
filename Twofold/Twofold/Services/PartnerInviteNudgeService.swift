//
//  PartnerInviteNudgeService.swift
//  Twofold
//
//  A solo user can now fully use Trips, Memories, and most Games — this is the "gentle
//  suggestion" that replaces the old hard partner gate on those flows. Simpler than
//  ReviewPromptService's cap: there's no per-kind "shown once ever" flag, since the whole
//  point is to keep suggesting pairing on later days, just never more than once on the same
//  day (a suggestion, not a nag).
//

import Foundation

enum PartnerInviteNudgeService {
    private static let lastShownAtKey = "partnerInviteNudge.lastShownAt"

    static func isEligibleToday() -> Bool {
        guard let lastShownAt = UserDefaults.standard.object(forKey: lastShownAtKey) as? Date else { return true }
        return !Calendar.current.isDateInToday(lastShownAt)
    }

    static func markShown() {
        UserDefaults.standard.set(Date.now, forKey: lastShownAtKey)
    }
}
