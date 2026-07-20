//
//  DistanceShareTheme.swift
//  Twofold
//

import SwiftUI

enum DistanceShareTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
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

    /// `.classic` reuses the app's own `Theme.backgroundGradient` (light sky blue into leaf
    /// green) rather than inventing a new palette — it's the default, so it should read as
    /// unmistakably "Twofold," not a separate design language. `.dark` is the deep, atmospheric
    /// alternative; `.pink` is a bright pastel pink-into-blue one, so the three read as
    /// genuinely distinct choices rather than three shades of moody.
    var backgroundGradient: LinearGradient {
        switch self {
        case .classic:
            Theme.backgroundGradient
        case .dark:
            LinearGradient(colors: [Color(hex: "060B18"), Color(hex: "0E2A52"), Color(hex: "12406E")], startPoint: .top, endPoint: .bottom)
        case .pink:
            // Explicit stop locations (not evenly spaced) so the blue takes over well before
            // the bottom edge, rather than only arriving right at the very end.
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "FFC0CB"), location: 0),
                    .init(color: Color(hex: "E8C6E0"), location: 0.3),
                    .init(color: Color(hex: "C6D6FF"), location: 0.6),
                    .init(color: Color(hex: "B8DFFF"), location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// The soft radial highlight glow layered over the background gradient's top.
    var glowColor: Color {
        switch self {
        case .classic: Color(hex: "9BD4FF")
        case .dark: Color(hex: "2E6FA8")
        case .pink: Color(hex: "FFF3FB")
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .classic: Theme.ink
        case .dark: .white
        case .pink: Color(hex: "4A1259")
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .classic: Theme.subtleInk
        case .dark: .white.opacity(0.65)
        case .pink: Color(hex: "4A1259").opacity(0.65)
        }
    }

    /// The comparison-stat line's color — needs to read clearly against its own background,
    /// not just be "the accent color" in the abstract.
    var accentTextColor: Color {
        switch self {
        case .classic: Color(hex: "2E86C1")
        case .dark: Color(hex: "9BD4FF")
        case .pink: Color(hex: "AD1477")
        }
    }
}
