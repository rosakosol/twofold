//
//  LiveActivityPalette.swift
//  LiveActivities
//
//  Deliberately NOT sharing Theme.swift with this target (widget extensions run under a tight
//  memory budget, and Theme is a large, evolving main-app surface) — instead a small, local
//  copy of just the colors this widget needs. Keep these hex values in sync with Theme.swift
//  by hand if that file's palette ever changes.
//

import SwiftUI

private extension Color {
    init(hex: String) {
        var hexValue = UInt64()
        Scanner(string: hex).scanHexInt64(&hexValue)
        let r = Double((hexValue & 0xFF0000) >> 16) / 255
        let g = Double((hexValue & 0x00FF00) >> 8) / 255
        let b = Double(hexValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum LiveActivityPalette {
    static let skyBlue = Color(hex: "4FA9E0")
    static let leafGreen = Color(hex: "6FBF8B")
    static let heartRed = Color(hex: "E85C6B")
    static let subtleInk = Color(hex: "5B6B7A")

    static func color(for status: FlightStatus?) -> Color {
        switch status {
        case .delayed, .cancelled, .diverted: heartRed
        case .landed, .arrived: leafGreen
        case .scheduled, .boarding, .departed, .inAir, .landingSoon: skyBlue
        case nil: subtleInk
        }
    }
}
