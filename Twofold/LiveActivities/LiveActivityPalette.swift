//
//  LiveActivityPalette.swift
//  LiveActivities
//
//  Deliberately NOT sharing Theme.swift with this target (widget extensions run under a tight
//  memory budget, and Theme is a large, evolving main-app surface) — instead a small, local
//  copy of just the colors this widget needs. Keep these hex values in sync with Theme.swift
//  by hand if that file's palette ever changes. Color(hex:) itself now lives in
//  Shared/TimeMath.swift (also needed there, module-wide within this target).
//

import SwiftUI

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
