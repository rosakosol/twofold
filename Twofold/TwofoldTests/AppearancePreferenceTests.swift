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

    // MARK: - Presented sheets

    /// The reported sequence, on a dark device: System → Light → System, with Settings open.
    ///
    /// SwiftUI stamps a presented controller's own `overrideUserInterfaceStyle` from
    /// `.preferredColorScheme`, and going back to "System" passes `nil` — "no preference", which
    /// does not clear what is already stamped. The sheet stayed light while the app behind it went
    /// dark. Light → Dark always worked, because that path writes a new value instead of needing
    /// one removed, which is why it only showed up in this one direction.
    /// Presentation isn't synchronous even with `animated: false` — asserting straight after
    /// `present` runs while `presentedViewController` is still nil, so `applyToWindows` never
    /// reaches the sheet and its untouched `.unspecified` passes a test for "the override was
    /// cleared". Awaiting the completion is what makes these tests about anything.
    @MainActor
    private func presentSheet(on root: UIViewController) async -> UIViewController {
        let sheet = UIViewController()
        await withCheckedContinuation { continuation in
            root.present(sheet, animated: false) { continuation.resume() }
        }
        return sheet
    }

    @MainActor
    private func dismiss(_ sheet: UIViewController) async {
        await withCheckedContinuation { continuation in
            sheet.dismiss(animated: false) { continuation.resume() }
        }
    }

    @MainActor
    @Test("returning to System clears an open sheet's override, not just the window's")
    func systemClearsAPresentedSheet() async throws {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        let window = try #require(windows.first, "no window to present from")
        let root = try #require(window.rootViewController)
        let sheet = await presentSheet(on: root)
        #expect(root.presentedViewController === sheet, "nothing was presented, so this proves nothing")
        defer { Task { await dismiss(sheet) } }

        AppearancePreference.current = .light
        AppearancePreference.applyToWindows()
        #expect(sheet.overrideUserInterfaceStyle == .light)

        AppearancePreference.current = .system
        AppearancePreference.applyToWindows()
        #expect(
            sheet.overrideUserInterfaceStyle == .unspecified,
            "the sheet kept its light override and stayed light on a dark device"
        )
    }

    @MainActor
    @Test("an open sheet follows an explicit switch too")
    func explicitSwitchReachesAPresentedSheet() async throws {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        let window = try #require(windows.first)
        let root = try #require(window.rootViewController)
        let sheet = await presentSheet(on: root)
        #expect(root.presentedViewController === sheet, "nothing was presented, so this proves nothing")
        defer { Task { await dismiss(sheet) } }

        AppearancePreference.current = .dark
        AppearancePreference.applyToWindows()
        #expect(sheet.overrideUserInterfaceStyle == .dark)
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
