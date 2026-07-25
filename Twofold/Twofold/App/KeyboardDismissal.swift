//
//  KeyboardDismissal.swift
//  Twofold
//

import UIKit

/// Installs one app-wide "tap anywhere to dismiss the keyboard" gesture, so individual screens
/// never need their own tap-outside handling or `@FocusState` just to close the keyboard. Lives at
/// the `UIWindow` level rather than as a SwiftUI view modifier because the app has no single root
/// `NavigationStack` — `MainTabView`'s five tabs, every `.sheet`/`.fullScreenCover` (paywall,
/// onboarding, game deep links, Add Memory, etc.) are all separate presentation contexts a
/// per-screen gesture wouldn't reach uniformly. A window-level recognizer sees every touch
/// regardless of which of those is currently on top.
enum KeyboardDismissal {
    private static var isInstalled = false

    @MainActor
    static func installOnce() {
        guard !isInstalled else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIWindow.twofold_dismissKeyboard))
        // Without this, the recognizer would swallow the touch before whatever's actually under
        // it (a button, a different text field) ever sees it — silently breaking every tap on
        // screen. `false` lets both fire: the keyboard resigns *and* the tapped control still
        // gets its own touch normally.
        tap.cancelsTouchesInView = false
        window.addGestureRecognizer(tap)
        isInstalled = true
    }
}

private extension UIWindow {
    @objc func twofold_dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
