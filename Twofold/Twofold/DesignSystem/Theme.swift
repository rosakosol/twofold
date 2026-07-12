//
//  Theme.swift
//  Twofold
//

import SwiftUI

// Color(hex:) and .interpolated(to:amount:) now live in Shared/TimeMath.swift — moved out so
// the widget extension (which can't import this file's Theme dependency) can use them too.

enum Theme {
    static let skyBlue = Color(hex: "4FA9E0")
    static let leafGreen = Color(hex: "6FBF8B")
    static let heartRed = Color(hex: "E85C6B")
    static let ink = Color(hex: "1C2A38")
    static let subtleInk = Color(hex: "5B6B7A")

    /// Bottom color of `backgroundGradient`, exposed so pinned bottom bars can fade
    /// scrolled content into the exact color the screen background ends on.
    static let backgroundBottom = Color(hex: "E4F4E6")

    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "D9EEF9"), backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Blue gradient for primary action buttons — lighter at the top, deeper at the
    /// bottom (centered on `skyBlue`) to give the capsule a subtle sense of depth.
    static let primaryButtonGradient = LinearGradient(
        colors: [Color(hex: "6EC1F0"), Color(hex: "3D8FC9")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBackground = Color(.secondarySystemGroupedBackground)

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
