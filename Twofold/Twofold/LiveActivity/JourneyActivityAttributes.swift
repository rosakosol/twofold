//
//  JourneyActivityAttributes.swift
//  Twofold
//
//  Describes the Live Activity shown on the Lock Screen / Dynamic Island while
//  a partner's flight is active. This struct alone does not render anything —
//  displaying it requires a Widget Extension target (Xcode > File > New >
//  Target > Widget Extension, with "Include Live Activity" checked) that
//  vends a matching `ActivityConfiguration`. Add that target from Xcode, then
//  share this file with the new extension.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct JourneyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: FlightStatus.RawValue
        var timeRemainingLabel: String
        var progress: Double
        var isReunion: Bool
    }

    var travelerName: String
    var flightNumber: String
    var originCode: String
    var destinationCode: String
}
#endif
