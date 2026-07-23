//
//  Couple.swift
//  Twofold
//

import Foundation

struct Couple: Identifiable, Hashable {
    let id: UUID
    var partnerA: Person
    var partnerB: Person
    var startedDatingOn: Date
    /// The real moment `redeem_invite_code` paired these two — nil only for the placeholder
    /// couple a not-yet-connected solo user starts with. Drives the daily-question/streak reset
    /// boundary (see `DailyActivityCard`), which is relative to this rather than a shared UTC
    /// midnight — not to be confused with `startedDatingOn`, the couple's own real-world
    /// anniversary date.
    var connectedAt: Date?
    /// The greatest distance ever recorded between this couple's two home cities — a persisted
    /// running max (see `update_couple_max_distance`), since home cities change over time and
    /// nothing else remembers how far apart you've been in the past. Nil for a couple that's
    /// never had both home cities set at once yet.
    var maxDistanceKm: Double?

    init(id: UUID = UUID(), partnerA: Person, partnerB: Person, startedDatingOn: Date, connectedAt: Date? = nil, maxDistanceKm: Double? = nil) {
        self.id = id
        self.partnerA = partnerA
        self.partnerB = partnerB
        self.startedDatingOn = startedDatingOn
        self.connectedAt = connectedAt
        self.maxDistanceKm = maxDistanceKm
    }

    /// Whether both partners share the same home city — used to soften copy that would
    /// otherwise frame all travel as done "for each other" (stats hero, snapshot card),
    /// which doesn't fit couples who live together and travel side by side.
    var sharesHomeCity: Bool {
        guard let a = partnerA.homeCity, let b = partnerB.homeCity else { return false }
        return a.city == b.city && a.country == b.country
    }

    func partner(_ id: Person.ID) -> Person? {
        [partnerA, partnerB].first { $0.id == id }
    }

    func otherPartner(than id: Person.ID) -> Person? {
        [partnerA, partnerB].first { $0.id != id }
    }
}
