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
import Observation

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

/// Owns the preference so SwiftUI can observe it. `MeasurementPreference.current` used to read
/// `UserDefaults` on every access, which persisted correctly but was invisible to SwiftUI — no
/// view ever registered a dependency on it, so changing the setting left every rendered distance
/// (and the Settings row's own subtitle) showing the old unit until something unrelated forced a
/// redraw. Reading through an `@Observable` property fixes that everywhere at once: any view body
/// touching `current` — directly, or via `distanceLabel`/`convertedValue`/`unitSuffix`, whose
/// default arguments are evaluated in the caller's context — now re-renders on change, with no
/// call-site changes required.
///
/// Deliberately not `@MainActor`, matching `AppModel` — `WidgetSnapshotWriter` reads this off the
/// view layer and annotating it would isolate a value that's only ever a two-case enum.
@Observable
final class MeasurementPreferenceStore {
    static let shared = MeasurementPreferenceStore()

    private static let key = "measurementSystem"

    /// The stored half. `@Observable` tracks it (private stored properties included), so reads of
    /// `system` register a dependency and writes fire a mutation.
    private var storedSystem: MeasurementSystem

    /// Written through to `UserDefaults` explicitly rather than via a `didSet` on a tracked stored
    /// property — the macro rewrites those into computed accessors, and a dropped observer would
    /// silently stop persisting, which is the exact bug this type exists to fix.
    var system: MeasurementSystem {
        get { storedSystem }
        set {
            storedSystem = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
        }
    }

    private init() {
        guard let raw = UserDefaults.standard.string(forKey: Self.key),
              let stored = MeasurementSystem(rawValue: raw) else {
            // Nothing chosen yet — follow the device locale rather than assuming metric. Set via
            // the stored property so a locale-derived default isn't written back to UserDefaults
            // as though it were a deliberate choice.
            storedSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
            return
        }
        storedSystem = stored
    }
}

enum MeasurementPreference {
    static var current: MeasurementSystem {
        get { MeasurementPreferenceStore.shared.system }
        set { MeasurementPreferenceStore.shared.system = newValue }
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
