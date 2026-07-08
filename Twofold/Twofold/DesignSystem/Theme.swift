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
