//
//  LiveActivityPalette.swift
//  LiveActivities
//
//  The widget extension's names for the brand colours. Values come from `Brand`
//  (Shared/BrandPalette.swift), which the app's Theme reads too, so the two cannot drift.
//

import SwiftUI

enum LiveActivityPalette {
    static let accent = Brand.accent
    static let coral = Brand.coral
    /// The Live Activity's one accent (docs/TWOFOLD_DESIGN.md, section 7), on its dark Lock Screen
    /// and Dynamic Island surfaces in both appearances.
    static let liveActivityAccent = Color(hex: 0x6AA5F5)
    /// Icons sitting on that accent, such as the plane on the progress bar.
    static let onAccent = Color(hex: 0x0B0F16)
}
