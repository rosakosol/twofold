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

    /// Applies the preference to every window the app owns.
    ///
    /// `.preferredColorScheme` at the root only reaches the hierarchy it's attached to. A sheet is
    /// a separate presentation, so Settings — itself presented as a sheet — kept whatever scheme it
    /// was created with: changing the setting updated the app behind it and left the screen holding
    /// the control untouched until it was dismissed and reopened. Reported exactly that way.
    ///
    /// Set on the window instead, which every presentation inside it inherits, including sheets,
    /// full-screen covers and alerts. `.preferredColorScheme` stays at the root as well; both read
    /// this same value, so they can't disagree.
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
