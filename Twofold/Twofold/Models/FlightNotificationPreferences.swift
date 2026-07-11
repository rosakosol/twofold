//
//  FlightNotificationPreferences.swift
//  Twofold
//
//  Per-partner, per-flight opt-in toggles. Each partner has their own row — one person muting
//  gate-change alerts for a flight doesn't affect what their partner receives.
//

import Foundation

struct FlightNotificationPreferences: Hashable {
    var flightID: UUID
    var profileID: UUID
    var gateTerminalChanges: Bool = true
    var delayOrCancellation: Bool = true
    var departure: Bool = true
    var landing: Bool = true
    var arrivalAtGate: Bool = true
    var baggageClaimUpdate: Bool = true

    /// Whether this preference set would allow a notification for the given event type.
    func allows(_ type: FlightStatusEventType) -> Bool {
        switch type {
        case .gateChange, .terminalChange: gateTerminalChanges
        case .delay, .cancelled, .diverted: delayOrCancellation
        case .departed, .airborne: departure
        case .arrivalTimeChange, .landed: landing
        case .arrivedAtGate: arrivalAtGate
        case .baggageClaim: baggageClaimUpdate
        case .scheduled: false
        }
    }
}
