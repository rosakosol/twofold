//
//  FlightUpdate.swift
//  Twofold
//

import SwiftUI

enum FlightUpdateKind: String, Codable, CaseIterable, Hashable {
    case mealService = "meal_service"
    case disruption
    case goingToSleep = "going_to_sleep"
    case custom

    var icon: String {
        switch self {
        case .mealService: "fork.knife"
        case .disruption: "exclamationmark.triangle.fill"
        case .goingToSleep: "moon.stars.fill"
        case .custom: "bubble.left.fill"
        }
    }

    var iconGradient: [Color] {
        switch self {
        case .mealService: [.orange, .yellow]
        case .disruption: [.red, .orange]
        case .goingToSleep: [.indigo, .blue]
        case .custom: [.gray, .gray.opacity(0.6)]
        }
    }

    var label: String {
        switch self {
        case .mealService: "Meal service"
        case .disruption: "Disruption"
        case .goingToSleep: "Going to sleep"
        case .custom: "Update"
        }
    }

    var defaultNote: String {
        switch self {
        case .mealService: "Meal service has started."
        case .disruption: "There's a delay or disruption."
        case .goingToSleep: "Heading to sleep for a while."
        case .custom: ""
        }
    }
}

struct FlightUpdate: Identifiable, Hashable {
    let id: UUID
    var kind: FlightUpdateKind
    var note: String?
    var createdAt: Date

    init(id: UUID = UUID(), kind: FlightUpdateKind, note: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.note = note
        self.createdAt = createdAt
    }
}
