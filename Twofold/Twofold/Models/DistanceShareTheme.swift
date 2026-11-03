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

    /// Colors drawn from `ShareCardPalette` (the `sky` accent on the dark canvas and the light
    /// pastel one, and the light `heart`), not copied out of it. All three are fixed:
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
        LinearGradient(colors: palette.canvas, startPoint: .top, endPoint: .bottom)
    }

    /// The `ShareCardPalette` this theme is.
    private var palette: ShareCardPalette {
        ShareCardPalette.resolve(accent, dark: self == .dark)
    }

    private var accent: ShareCardAccent { self == .pink ? .heart : .sky }

    /// The soft radial highlight glow layered over the background gradient's top — the accent's
    /// own base hue (`DistanceShareCard` applies the opacity).
    var glowColor: Color { ShareCardPalette.glowHue(accent, dark: self == .dark) }

    var primaryTextColor: Color { palette.foreground }

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
    var accentTextColor: Color { palette.accent }
}
