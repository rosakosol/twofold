//
//  AppLockService.swift
//  Twofold
//
//  Optional local re-authentication gate, separate from (and layered on top of) the Supabase
//  session — that session alone lets anyone with the unlocked device straight into the app with
//  no further check. Opt-in via Settings, since not everyone wants an extra tap to open an app
//  they've already unlocked their phone to reach; `RootView` is what actually shows/hides the
//  lock screen and decides when to re-lock (entering the background).
//

import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLockService {
    private static let enabledKey = "appLockEnabled"

    /// Whether the lock screen should currently be covering the app. Starts pre-set from the
    /// persisted preference (not just `false`) so a cold launch with the lock already turned on
    /// shows the lock screen from the very first frame, before any sensitive content ever
    /// renders — rather than flashing real content and locking a moment later.
    var isLocked: Bool

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Whether this device has *any* passcode/biometric set up at all — if not, the Settings
    /// toggle should be disabled rather than offering a lock nothing could ever unlock.
    var isAvailableOnDevice: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Name of whatever authentication this device actually offers, for the Settings row's label
    /// ("Require Face ID" reads a lot better than a generic "biometric lock," and some devices
    /// only have Touch ID, Optic ID, or no biometrics enrolled at all).
    var methodName: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return "Passcode" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Called when the app should re-lock — `RootView` calls this on entering the background.
    /// No-op while the setting is off, so callers don't each need their own guard.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Prompts Face ID/Touch ID/Optic ID/passcode and unlocks on success.
    /// `.deviceOwnerAuthentication` (not `.deviceOwnerAuthenticationWithBiometrics`) so a device
    /// with biometrics disabled, unenrolled, or exhausted after failed attempts still falls back
    /// to the passcode instead of locking the user out of their own app entirely.
    @discardableResult
    func authenticate() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode/biometric configured on this device at all — can't lock against
            // nothing. Fail open rather than strand the user with no way back in.
            isLocked = false
            return true
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Twofold")
            if success { isLocked = false }
            return success
        } catch {
            return false
        }
    }
}
