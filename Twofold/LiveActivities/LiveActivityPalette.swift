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
    static let success = Brand.success
    static let coral = Brand.coral
    static let textSecondary = Brand.textSecondary

    /// Status is never colour alone: every caller pairs this with the status word and icon.
    static func color(for status: FlightStatus?) -> Color {
        switch status {
        case .delayed: Brand.warning
        case .cancelled, .diverted: Brand.error
        case .landed, .arrived: Brand.success
        case .scheduled, .boarding, .departed, .inAir, .landingSoon: Brand.accent
        case nil: Brand.textSecondary
        }
    }
}
