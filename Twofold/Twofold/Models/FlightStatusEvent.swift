//
//  FlightStatusEvent.swift
//  Twofold
//
//  Provider-sourced event history (gate changes, delays, departure/landing, etc.), written
//  server-side by the AeroAPI sync pipeline. Distinct from `FlightUpdate` (FlightUpdate.swift),
//  which is the traveler's own self-reported meal/disruption/sleep notes — a different,
//  older feature that stays as-is.
//

import SwiftUI

enum FlightStatusEventType: String, Codable, CaseIterable, Hashable {
    case scheduled
    case delay
    case gateChange = "gate_change"
    case terminalChange = "terminal_change"
    case departed
    case airborne
    case arrivalTimeChange = "arrival_time_change"
    case landed
    case arrivedAtGate = "arrived_at_gate"
    case baggageClaim = "baggage_claim"
    case cancelled
    case diverted

    var icon: String {
        switch self {
        case .scheduled: "calendar"
        case .delay: "clock.badge.exclamationmark"
        case .gateChange: "door.left.hand.open"
        case .terminalChange: "building.2"
        case .departed: "airplane.departure"
        case .airborne: "airplane"
        case .arrivalTimeChange: "clock.arrow.circlepath"
        case .landed: "airplane.arrival"
        case .arrivedAtGate: "checkmark.circle.fill"
        case .baggageClaim: "suitcase.rolling.fill"
        case .cancelled: "xmark.circle.fill"
        case .diverted: "arrow.triangle.branch"
        }
    }

    var isUrgent: Bool {
        switch self {
        case .delay, .cancelled, .diverted, .gateChange, .terminalChange: true
        default: false
        }
    }

    /// Worth showing in the updates timeline. Excludes `.scheduled` (that's just the moment the
    /// flight was added to tracking, not a real schedule change — misleading to display as an
    /// "update") and `.airborne` (redundant milestone noise seconds after `.departed`).
    var isKeyUpdate: Bool {
        switch self {
        case .scheduled, .airborne: false
        default: true
        }
    }

    /// Human copy for a generic occurrence of this event type — used when a specific new
    /// value isn't available to interpolate into the message.
    var genericLabel: String {
        switch self {
        case .scheduled: "Flight scheduled"
        case .delay: "Flight delayed"
        case .gateChange: "Gate changed"
        case .terminalChange: "Terminal changed"
        case .departed: "Departed"
        case .airborne: "In the air"
        case .arrivalTimeChange: "New arrival time"
        case .landed: "Landed"
        case .arrivedAtGate: "Arrived at gate"
        case .baggageClaim: "Baggage claim assigned"
        case .cancelled: "Flight cancelled"
        case .diverted: "Flight diverted"
        }
    }

    /// Human copy incorporating the event's new value, when one exists (e.g. "Departure gate
    /// changed to 7"). Falls back to `genericLabel` when there's nothing to interpolate.
    /// `timeZone` is only used for `.arrivalTimeChange`, whose stored value is a raw ISO8601
    /// instant from the server — shown in the destination airport's local time when known,
    /// falling back to the device's own time zone.
    func label(newValue: String?, timeZone: TimeZone? = nil) -> String {
        guard let newValue, !newValue.isEmpty else { return genericLabel }
        switch self {
        case .gateChange: return "Gate changed to \(newValue)"
        case .terminalChange: return "Terminal updated to \(newValue)"
        case .arrivalTimeChange: return "New arrival time: \(Self.formattedTime(newValue, timeZone: timeZone) ?? newValue)"
        case .baggageClaim: return "Baggage claim: \(newValue)"
        case .delay: return "Flight delayed by \(newValue)"
        default: return genericLabel
        }
    }

    private static func formattedTime(_ iso: String, timeZone: TimeZone?) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute())
    }
}

struct FlightStatusEvent: Identifiable, Hashable {
    let id: UUID
    var flightID: UUID
    var type: FlightStatusEventType
    var previousValue: String?
    var newValue: String?
    var occurredAt: Date
    var source: String

    init(id: UUID = UUID(), flightID: UUID, type: FlightStatusEventType, previousValue: String? = nil, newValue: String? = nil, occurredAt: Date = .now, source: String = "poll") {
        self.id = id
        self.flightID = flightID
        self.type = type
        self.previousValue = previousValue
        self.newValue = newValue
        self.occurredAt = occurredAt
        self.source = source
    }

    func label(timeZone: TimeZone? = nil) -> String { type.label(newValue: newValue, timeZone: timeZone) }
}
