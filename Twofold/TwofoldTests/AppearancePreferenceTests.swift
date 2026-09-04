//
//  AppearancePreferenceTests.swift
//  TwofoldTests
//
//  The appearance override, which now lives in exactly one place.
//
//  It used to live in two: `.preferredColorScheme` at the root and an override on the window. The
//  first writes the scheme into the SwiftUI environment, and a sheet inherits the environment it
//  was presented with — so Settings, itself a sheet, kept whatever scheme it opened with, and
//  returning to "System" passed `nil`, which is *no preference* rather than *clear the
//  preference*. The window is the only source now, and a presentation inherits it.

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
    /// Asserts on the style the sheet *resolves to*, not on an override set on it. That distinction
    /// is the fix: an earlier attempt stamped every presented controller explicitly and the unit
    /// test for it passed while the app was still wrong, because the real cause was
    /// `.preferredColorScheme` at the root baking a scheme into the sheet's environment, which
    /// outranks the controller's own override. With that modifier gone the window is the single
    /// source, and a presentation inherits it.
    @MainActor
    @Test("an open sheet follows the preference, including back to System")
    func anOpenSheetFollowsThePreference() async throws {
        let original = AppearancePreference.current
        defer { AppearancePreference.current = original; AppearancePreference.applyToWindows() }

        let window = try #require(windows.first, "no window to present from")
        let root = try #require(window.rootViewController)
        let sheet = await presentSheet(on: root)
        #expect(root.presentedViewController === sheet, "nothing was presented, so this proves nothing")
        defer { Task { await dismiss(sheet) } }

        #expect(await resolvedStyle(of: sheet, after: .light) == .light)
        #expect(await resolvedStyle(of: sheet, after: .dark) == .dark)

        // "System" can't assert a fixed value — it depends on the simulator's own appearance — so
        // the invariant is that the sheet lands wherever the window lands. That is exactly what
        // was broken: the window went dark and the sheet stayed light.
        let underSystem = await resolvedStyle(of: sheet, after: .system)
        #expect(underSystem == window.traitCollection.userInterfaceStyle)
        #expect(window.overrideUserInterfaceStyle == .unspecified)
    }

    /// Trait changes propagate on the next turn of the run loop, so reading straight after the
    /// write returns the *previous* value — which is how a version of this test once passed
    /// against an unchanged sheet.
    @MainActor
    private func resolvedStyle(
        of controller: UIViewController,
        after appearance: AppAppearance
    ) async -> UIUserInterfaceStyle {
        AppearancePreference.current = appearance
        AppearancePreference.applyToWindows()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        return controller.traitCollection.userInterfaceStyle
    }

    /// Presentation isn't synchronous even with `animated: false` — asserting straight after
    /// `present` runs while `presentedViewController` is still nil.
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

    // MARK: - The stored value

    /// `colorScheme` is no longer used to style the app — the window override is — but it stays
    /// as the SwiftUI spelling of the same choice, so anything reading it agrees with the window.
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
