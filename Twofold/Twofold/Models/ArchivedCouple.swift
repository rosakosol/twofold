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
