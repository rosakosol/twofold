//
//  Theme.swift
//  Twofold
//

import SwiftUI

// Color(hex:) and .interpolated(to:amount:) now live in Shared/TimeMath.swift — moved out so
// the widget extension (which can't import this file's Theme dependency) can use them too.

enum Theme {
    // Every token below except `cardBackground`/`DayNight.*` is `Color(light:dark:)` (see
    // `Shared/TimeMath.swift`) rather than a flat hex literal, so the whole app adapts to system
    // appearance from this one file — see the ~162 feature files that already draw from `Theme.*`
    // instead of defining their own colors.
    static let skyBlue = Color(light: "4FA9E0", dark: "63B8EA")
    static let leafGreen = Color(light: "6FBF8B", dark: "7DD1A0")
    static let heartRed = Color(light: "E85C6B", dark: "F1727F")
    static let ink = Color(light: "1C2A38", dark: "ECF1F5")
    static let subtleInk = Color(light: "5B6B7A", dark: "94A3B3")

    /// Bottom color of `backgroundGradient`, exposed so pinned bottom bars can fade
    /// scrolled content into the exact color the screen background ends on.
    static let backgroundBottom = Color(light: "E4F4E6", dark: "16241D")

    /// Dark mode is deliberately its own deep gradient (blue-slate down to green-black), not just
    /// a darkened version of the light gradient's pale pastel — that would read as washed out
    /// rather than a genuine dark background.
    static let backgroundGradient = LinearGradient(
        colors: [Color(light: "D9EEF9", dark: "13202B"), backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Blue gradient for primary action buttons — lighter at the top, deeper at the
    /// bottom (centered on `skyBlue`) to give the capsule a subtle sense of depth.
    static let primaryButtonGradient = LinearGradient(
        colors: [Color(light: "6EC1F0", dark: "72C6F2"), Color(light: "3D8FC9", dark: "4696CE")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBackground = Color(.secondarySystemGroupedBackground)

    /// Selected-state border for onboarding's option cards — blue-to-green, echoing the two
    /// core accent colors rather than a flat single-color highlight.
    static let selectionGradient = LinearGradient(
        colors: [skyBlue, leafGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Day/night palette for the timezone card, blended continuously by hour-of-day.
    enum DayNight {
        static let nightTop = Color(hex: "0B1D3A")
        static let nightBottom = Color(hex: "1B2A4A")
        static let dayTop = Color(hex: "3E8FD9")
        static let dayBottom = Color(hex: "F2A93C")
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 999
    }
}

extension Person {
    /// A small palette so mock partners get distinct, deterministic colors.
    static let palette: [Color] = [Theme.skyBlue, Theme.heartRed, Theme.leafGreen, .orange, .purple]
}
