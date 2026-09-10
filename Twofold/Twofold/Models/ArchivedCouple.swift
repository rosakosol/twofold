//
//  ArchivedCouple.swift
//  Twofold
//
//  A past, dissolved partnership — the couple row (and everything scoped to it: trips,
//  memories, flights, game sessions, drawing pads) still exists in the backend, just no longer
//  active. Only ever surfaced in Settings' "Archived data" screen.
//

import Foundation

struct ArchivedCouple: Identifiable, Hashable {
    let id: UUID
    var partnerName: String
    var startedDatingOn: Date?
    var dissolvedAt: Date?
    /// When this archive is permanently deleted: 90 days after it ended, automatically, whether or
    /// not either partner asks. Null only if the row predates that clock.
    var scheduledPurgeAt: Date?
    /// Hidden from this person's own archive list. Non-destructive and unilateral — it says
    /// nothing about the partner's view, and nothing has been deleted.
    var isHidden: Bool = false

    /// Whole days left before it goes, floored, never negative. Nil when there is no deadline.
    ///
    /// Floored deliberately: "3 days left" has to mean at least three, so someone counting on it
    /// is never surprised a day early. Deletion runs on a nightly job, so the real moment is
    /// always at or after the stamp.
    var daysUntilDeletion: Int? {
        guard let scheduledPurgeAt else { return nil }
        let seconds = scheduledPurgeAt.timeIntervalSinceNow
        guard seconds > 0 else { return 0 }
        return Int(seconds / 86_400)
    }

    /// Close enough that the countdown should be red rather than grey. A fortnight, because that
    /// is roughly the last point at which someone could still notice, decide, and export.
    var deletionIsImminent: Bool { (daysUntilDeletion ?? .max) <= 14 }

    /// How the countdown reads on the archive list and detail screen.
    var deletionNotice: String? {
        guard let days = daysUntilDeletion else { return nil }
        switch days {
        case 0: return "Deletes today"
        case 1: return "Deletes tomorrow"
        default: return "Deletes in \(days) days"
        }
    }
}

struct ArchivedCoupleSummary: Hashable {
    var tripCount: Int
    var memoryCount: Int
    var flightCount: Int
    var gameSessionCount: Int

    var isEmpty: Bool {
        tripCount == 0 && memoryCount == 0 && flightCount == 0 && gameSessionCount == 0
    }
}
