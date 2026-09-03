//
//  AppearancePreferenceTests.swift
//  TwofoldTests
//
//  The appearance override, and the part of it that had to move.
//
//  `.preferredColorScheme` at the root only reaches the hierarchy it's attached to, so Settings —
//  presented as a sheet — kept whatever scheme it was created with. Changing the setting restyled
//  the app behind it and left the screen holding the control untouched until it was dismissed and
//  reopened. The override goes on the window now, which every presentation inside it inherits.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Twofold

@Suite(.serialized)
struct AppearancePreferenceTests {

    /// Every window the app owns, which is what `applyToWindows` walks.
    @MainActor
    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    @MainActor
    private func applying(_ appearance: AppAppearance) -> [UIUserInterfaceStyle] {
        AppearancePreference.current = appearance
        AppearancePreference.applyToWindows()
        return windows.map(\.overrideUserInterfaceStyle)
    }

    // MARK: - The window override

    @MainActor
    @Test("choosing Dark overrides the window, not just the root hierarchy")
    func darkAppliesToWindows() {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        let styles = applying(.dark)
        #expect(!styles.isEmpty, "no window to style — this test can't say anything")
        #expect(styles.allSatisfy { $0 == .dark })
    }

    @MainActor
    @Test("choosing Light overrides the window")
    func lightAppliesToWindows() {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        #expect(applying(.light).allSatisfy { $0 == .light })
    }

    /// "System" has to *clear* the override rather than pick one, or switching back from Dark would
    /// leave the app stuck in whichever it was last told.
    @MainActor
    @Test("choosing System clears the override rather than picking a side")
    func systemClearsTheOverride() {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        _ = applying(.dark)
        #expect(applying(.system).allSatisfy { $0 == .unspecified })
    }

    @MainActor
    @Test("switching between the two doesn't leave the previous one behind")
    func switchingIsClean() {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        _ = applying(.dark)
        #expect(applying(.light).allSatisfy { $0 == .light })
        #expect(applying(.dark).allSatisfy { $0 == .dark })
    }

    // MARK: - The stored value

    /// The window override and `.preferredColorScheme` both read this, which is what keeps them
    /// from disagreeing.
    @Test("the SwiftUI scheme matches what the window is told")
    func schemeMatchesStyle() {
        #expect(AppAppearance.system.colorScheme == nil, "nil is how SwiftUI spells 'follow the system'")
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("the choice survives being written and read back")
    func preferencePersists() {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original }

        AppearancePreference.current = .dark
        #expect(AppearancePreferenceStore.shared.appearance == .dark)
        #expect(UserDefaults.standard.string(forKey: "appAppearance") == AppAppearance.dark.rawValue)
    }
}
