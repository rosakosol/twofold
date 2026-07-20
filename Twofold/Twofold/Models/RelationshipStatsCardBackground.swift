//
//  RelationshipStatsCardBackground.swift
//  Twofold
//

import SwiftUI

/// The Relationship Stats snapshot card's background choice — `.auto` is the default warm
/// sunset gradient, everything else is a fixed, curated alternative for a couple who'd rather
/// pick a different look. A "solid" look is just a gradient whose two stops happen to match —
/// no separate code path needed.
enum RelationshipStatsCardBackground: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case ocean = "Ocean"
    case midnight = "Midnight"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .auto: [Color(hex: "FF9A5A"), Color(hex: "C2417A")]
        case .ocean: [Color(hex: "1B5E82"), Color(hex: "1D6B4A")]
        case .midnight: [Color(hex: "10192B"), Color(hex: "10192B")]
        }
    }
}
