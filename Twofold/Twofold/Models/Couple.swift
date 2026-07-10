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

    init(id: UUID = UUID(), partnerA: Person, partnerB: Person, startedDatingOn: Date) {
        self.id = id
        self.partnerA = partnerA
        self.partnerB = partnerB
        self.startedDatingOn = startedDatingOn
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
