//
//  RelationshipStatsCardBackground.swift
//  Twofold
//

import SwiftUI

/// The Relationship Stats snapshot card's look. `.classic` is the default — a white card that
/// mirrors the in-app `RelationshipStatsCard` (the same milestone tiles, icons, and layout,
/// just rendered standalone for sharing) rather than the photo-story layout `.auto` uses. Only
/// two options now (Ocean/Midnight removed) — a "solid" look would just be a gradient whose two
/// stops happen to match, no separate case needed if a plain-color option comes back later.
enum RelationshipStatsCardBackground: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case auto = "Sunset"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .classic: [Color.white, Color.white]
        case .auto: [Color(hex: "FF9A5A"), Color(hex: "C2417A")]
        }
    }
}
