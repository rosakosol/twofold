//
//  TimeMath.swift
//  Twofold
//
//  Pure day/night math, shared between the main app's TimeZoneCard and the widget extension's
//  Partner's Time / Time & Weather widgets (which can't import the main app module, so this has
//  to live somewhere both targets can see). Color(hex:) lives here too, for the same reason —
//  it has no Theme dependency of its own, so moving it out doesn't pull Theme.swift along.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
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

enum TimeMath {
    static func hourFraction(in timeZone: TimeZone, at date: Date) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    /// 0 = darkest (around 1am), 1 = brightest (around 1pm), smoothly continuous through the day.
    static func daylightFactor(hour: Double) -> Double {
        (1 + cos(2 * .pi * (hour - 13) / 24)) / 2
    }

    static func timeString(in timeZone: TimeZone, at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute())
    }

    /// Same hex values as Theme.DayNight — duplicated here (not imported from Theme.swift,
    /// which stays main-app-only) since these four colors are all a widget needs from it.
    enum DayNight {
        static let nightTop = Color(hex: "0B1D3A")
        static let nightBottom = Color(hex: "1B2A4A")
        static let dayTop = Color(hex: "3E8FD9")
        static let dayBottom = Color(hex: "F2A93C")
    }
}
