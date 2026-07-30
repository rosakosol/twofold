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
    /// (`sky` accent, dark "Aurora" canvas / light "Daylight" pastel canvas). `.classic` ("Light")
    /// follows system appearance — it's the default, so it should read as unmistakably "Twofold,"
    /// not a separate design language — while `.dark` and `.pink` are explicit, appearance-
    /// independent picks (the same handoff's dark-sky and light-heart canvases), so choosing one
    /// always looks the same regardless of the system's own light/dark setting.
    var backgroundGradient: LinearGradient {
        switch self {
        case .classic:
            LinearGradient(
                colors: [
                    Color(light: "E4F2FC", dark: "123045"),
                    Color(light: "D3E9F8", dark: "0C2233"),
                    Color(light: "DFF2EC", dark: "08161F"),
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
        case .classic: Color(light: "6EC1F0", dark: "4FA9E0")
        case .dark: Color(hex: "4FA9E0")
        case .pink: Color(hex: "E85C6B")
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .classic: Color(light: "16232F", dark: "F4F9FC")
        case .dark: Color(hex: "F4F9FC")
        case .pink: Color(hex: "16232F")
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .classic: Color(light: "52657A", dark: "AEC0CD")
        case .dark: Color(hex: "AEC0CD")
        case .pink: Color(hex: "16232F").opacity(0.65)
        }
    }

    /// The comparison-stat line's color — the accent's own text-safe tone (never the fill tone),
    /// needs to read clearly against its own background, not just be "the accent color" in the
    /// abstract.
    var accentTextColor: Color {
        switch self {
        case .classic: Color(light: "1F6F9E", dark: "8ACFF5")
        case .dark: Color(hex: "8ACFF5")
        case .pink: Color(hex: "C2334A")
        }
    }
}
