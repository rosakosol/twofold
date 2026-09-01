//
//  DistanceShareTheme.swift
//  Twofold
//

import SwiftUI

enum DistanceShareTheme: String, CaseIterable, Identifiable {
    case classic = "Light"
    case dark = "Dark"
    case pink = "Pink"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .classic: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .pink: "heart.fill"
        }
    }

    /// Colors drawn straight from the dark-mode/Daylight handoff's `ShareCard` canvas table
    /// (`sky` accent, dark "Aurora" canvas / light "Daylight" pastel canvas). All three are fixed:
    /// `.classic` is the light canvas, `.dark` the dark one and `.pink` the light-heart one, so
    /// picking a theme looks the same regardless of the system's own setting.
    ///
    /// `.classic` used to be the exception, built from `Color(light:dark:)` so it tracked the
    /// device. That made the swatch labelled "Light" render dark for anyone in dark mode — and
    /// worse, it disagreed with the file it produced, since the exported image renders light. Users
    /// saw a dark preview and shared a light card.
    ///
    /// A share card is a leaf image that leaves the app: it has to look right in Photos and in a
    /// Messages thread, where the sender's appearance setting is not in evidence — which is the
    /// same reason `ShareCardPalette` exists at all rather than these cards using `Theme.*`. A
    /// theme picker naming a colour should produce that colour.
    var backgroundGradient: LinearGradient {
        switch self {
        case .classic:
            LinearGradient(
                colors: [
                    Color(hex: "E4F2FC"),
                    Color(hex: "D3E9F8"),
                    Color(hex: "DFF2EC"),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .dark:
            LinearGradient(colors: [Color(hex: "123045"), Color(hex: "0C2233"), Color(hex: "08161F")], startPoint: .top, endPoint: .bottom)
        case .pink:
            LinearGradient(colors: [Color(hex: "FDEAEC"), Color(hex: "FBE0E4"), Color(hex: "F6E6EE")], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The soft radial highlight glow layered over the background gradient's top — the accent's
    /// own base hue (`DistanceShareCard` applies the opacity).
    var glowColor: Color {
        switch self {
        case .classic: Color(hex: "6EC1F0")
        case .dark: Color(hex: "4FA9E0")
        case .pink: Color(hex: "E85C6B")
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .classic: Color(hex: "16232F")
        case .dark: Color(hex: "F4F9FC")
        case .pink: Color(hex: "16232F")
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .classic: Color(hex: "52657A")
        case .dark: Color(hex: "AEC0CD")
        case .pink: Color(hex: "16232F").opacity(0.65)
        }
    }

    /// The comparison-stat line's color — the accent's own text-safe tone (never the fill tone),
    /// needs to read clearly against its own background, not just be "the accent color" in the
    /// abstract.
    var accentTextColor: Color {
        switch self {
        case .classic: Color(hex: "1F6F9E")
        case .dark: Color(hex: "8ACFF5")
        case .pink: Color(hex: "C2334A")
        }
    }
}
