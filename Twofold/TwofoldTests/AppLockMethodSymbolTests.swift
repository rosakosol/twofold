//
//  AppLockMethodSymbolTests.swift
//  TwofoldTests
//
//  The unlock button's glyph has to name the same method as its label.
//
//  It used to pick "faceid" for anything that was not "Passcode", so every Touch ID phone (iPhone
//  Duo among them) showed a Face ID face beside the words "Unlock with Touch ID".
//

import LocalAuthentication
import Testing
@testable import Twofold

@Suite("App lock names and draws the same method")
@MainActor
struct AppLockMethodSymbolTests {

    @Test("each biometry type gets its own glyph", arguments: [
        (LABiometryType.faceID, "faceid"),
        (LABiometryType.touchID, "touchid"),
        (LABiometryType.opticID, "opticid"),
        (LABiometryType.none, "lock.fill"),
    ])
    func glyph(biometry: LABiometryType, expected: String) {
        #expect(AppLockService.methodSymbolName(for: biometry, canEvaluate: true) == expected)
    }

    @Test("Touch ID is never drawn as a Face ID face")
    func touchIDIsNotFaceID() {
        #expect(AppLockService.methodName(for: .touchID, canEvaluate: true) == "Touch ID")
        #expect(AppLockService.methodSymbolName(for: .touchID, canEvaluate: true) != "faceid")
    }

    /// Without a usable policy `biometryType` is not meaningful, and the label already says
    /// "Passcode" in that case; the glyph has to agree.
    @Test("no usable policy is a passcode, whatever biometryType says")
    func noPolicyIsPasscode() {
        #expect(AppLockService.methodName(for: .faceID, canEvaluate: false) == "Passcode")
        #expect(AppLockService.methodSymbolName(for: .faceID, canEvaluate: false) == "lock.fill")
    }
}
