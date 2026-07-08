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

    func partner(_ id: Person.ID) -> Person? {
        [partnerA, partnerB].first { $0.id == id }
    }

    func otherPartner(than id: Person.ID) -> Person? {
        [partnerA, partnerB].first { $0.id != id }
    }
}
