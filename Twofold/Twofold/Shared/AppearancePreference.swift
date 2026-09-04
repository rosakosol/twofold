//
//  AppearancePreference.swift
//  Twofold
//
//  Device-local display preference (not synced to the backend — this is how *this device*
//  renders the app, not shared couple data) — lets someone override Light/Dark independently of
//  the system setting. Same @Observable-store-plus-UserDefaults shape as MeasurementPreference,
//  for the same reason: a view reading `current` (directly, or via `colorScheme`) needs to
//  actually re-render when this changes, not just persist correctly.
//

import Observation
import SwiftUI
import UIKit

enum AppAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "don't override" — handed straight to `.preferredColorScheme`, which already
    /// treats `nil` as "follow the system setting."
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Owns the preference so SwiftUI can observe it — see `MeasurementPreferenceStore`'s identical
/// reasoning. Deliberately not `@MainActor`, matching that store and `AppModel`.
@Observable
final class AppearancePreferenceStore {
    static let shared = AppearancePreferenceStore()

    private static let key = "appAppearance"

    /// The stored half. `@Observable` tracks it (private stored properties included), so reads of
    /// `appearance` register a dependency and writes fire a mutation.
    private var storedAppearance: AppAppearance

    /// Written through to `UserDefaults` explicitly rather than via a `didSet` on a tracked stored
    /// property — the macro rewrites those into computed accessors, and a dropped observer would
    /// silently stop persisting, which is the exact bug this shape exists to avoid.
    var appearance: AppAppearance {
        get { storedAppearance }
        set {
            storedAppearance = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
        }
    }

    private init() {
        guard let raw = UserDefaults.standard.string(forKey: Self.key),
              let stored = AppAppearance(rawValue: raw) else {
            storedAppearance = .system
            return
        }
        storedAppearance = stored
    }
}

enum AppearancePreference {
    static var current: AppAppearance {
        get { AppearancePreferenceStore.shared.appearance }
        set { AppearancePreferenceStore.shared.appearance = newValue }
    }

    /// Applies the preference to every window the app owns — the only mechanism that does.
    ///
    /// The app used to carry `.preferredColorScheme` at the root as well, and the two disagreed.
    /// That modifier writes the scheme into the SwiftUI environment, and a sheet inherits the
    /// environment it was presented with, so choosing Light baked light into an open Settings
    /// sheet. Returning to "System" passes `nil`, which means *no preference* rather than *clear
    /// the preference* — leaving the sheet light while the app behind it went dark, until Settings
    /// was closed and reopened. Reported twice.
    ///
    /// Measured, on a dark device with Settings open and both mechanisms in place: after switching
    /// back to System the window resolved to dark and the sheet's own hosting controller still
    /// resolved to light — even with its `overrideUserInterfaceStyle` explicitly cleared, because
    /// the environment it captured outranked it. With `.preferredColorScheme` removed, the same
    /// switch resolves the sheet to dark on its own. A window's override propagates into every
    /// presentation inside it, so nothing needs to be walked or stamped per-controller.
    @MainActor
    static func applyToWindows() {
        let style: UIUserInterfaceStyle = switch current {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
