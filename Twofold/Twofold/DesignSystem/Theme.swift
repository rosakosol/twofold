//
//  Theme.swift
//  Twofold
//

import SwiftUI

extension Color {
    init(hex: String) {
        var hexValue = UInt64()
        Scanner(string: hex).scanHexInt64(&hexValue)
        let r = Double((hexValue & 0xFF0000) >> 16) / 255
        let g = Double((hexValue & 0x00FF00) >> 8) / 255
        let b = Double(hexValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Component-wise blend toward `other`, used for the timezone card's continuous day/night gradient.
    func interpolated(to other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            opacity: a1 + (a2 - a1) * t
        )
    }
}

enum Theme {
    static let skyBlue = Color(hex: "4FA9E0")
    static let leafGreen = Color(hex: "6FBF8B")
    static let heartRed = Color(hex: "E85C6B")
    static let ink = Color(hex: "1C2A38")
    static let subtleInk = Color(hex: "5B6B7A")

    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "D9EEF9"), Color(hex: "E4F4E6")],
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
