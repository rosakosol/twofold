//
//  MeasurementPreference.swift
//  Twofold
//
//  Device-local display preference (not synced to the backend — this is how distances render
//  on this device, not shared couple data). Lives in Shared/ so a future widget could read it
//  too, even though nothing does yet. Uses Measurement<UnitLength> for correct km->mi
//  conversion rather than a hand-rolled multiplier.
//

import Foundation

enum MeasurementSystem: String, Codable, CaseIterable {
    case metric
    case imperial

    var displayName: String {
        switch self {
        case .metric: "Metric (km)"
        case .imperial: "Imperial (mi)"
        }
    }
}

enum MeasurementPreference {
    private static let key = "measurementSystem"

    static var current: MeasurementSystem {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key), let system = MeasurementSystem(rawValue: raw) else {
                let usesMetric = (Locale.current.measurementSystem == .metric)
                return usesMetric ? .metric : .imperial
            }
            return system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// Formats a kilometre distance according to the current preference, e.g. "1,234 km" or "767 mi".
    static func distanceLabel(km: Double, system: MeasurementSystem = MeasurementPreference.current) -> String {
        "\(Int(convertedValue(km: km, system: system).rounded()).formatted()) \(unitSuffix(system: system))"
    }

    /// The bare numeric value in the current preference's unit — for call sites that style the
    /// number and unit text separately rather than using `distanceLabel`'s single string.
    static func convertedValue(km: Double, system: MeasurementSystem = MeasurementPreference.current) -> Double {
        switch system {
        case .metric: km
        case .imperial: Measurement(value: km, unit: UnitLength.kilometers).converted(to: .miles).value
        }
    }

    static func unitSuffix(system: MeasurementSystem = MeasurementPreference.current) -> String {
        switch system {
        case .metric: "km"
        case .imperial: "mi"
        }
    }
}
