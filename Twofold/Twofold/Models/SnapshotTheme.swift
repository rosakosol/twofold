//
//  SnapshotTheme.swift
//  Twofold
//

import SwiftUI

enum SnapshotTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case earth = "Earth"
    case minimal = "Minimal"
    case blueprint = "Blueprint"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .classic: "sparkles"
        case .earth: "globe.americas.fill"
        case .minimal: "circle.slash"
        case .blueprint: "square.grid.2x2"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .classic:
            LinearGradient(colors: [Color(hex: "CFE8F5"), Color(hex: "E3F3E1")], startPoint: .top, endPoint: .bottom)
        case .earth:
            LinearGradient(colors: [Color(hex: "0B3D91"), Color(hex: "1C7ED6")], startPoint: .top, endPoint: .bottom)
        case .minimal:
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom)
        case .blueprint:
            LinearGradient(colors: [Color(hex: "0A2A43"), Color(hex: "123A5C")], startPoint: .top, endPoint: .bottom)
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .classic, .minimal: Color(hex: "1C2A38")
        case .earth, .blueprint: .white
        }
    }

    var accentTextColor: Color {
        switch self {
        case .classic: Color(hex: "2E86C1")
        case .earth: Color(hex: "9BD4FF")
        case .minimal: Color(hex: "3A7BD5")
        case .blueprint: Color(hex: "6FD3FF")
        }
    }
}
