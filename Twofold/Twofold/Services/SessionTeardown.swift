//
//  SessionTeardown.swift
//  Twofold
//
//  The calls `AppModel.signOut()` and `deleteAccount()` make on the way out, behind a protocol so
//  a unit test can see which ran and in what order. Order is most of what can go wrong here: a
//  cleanup that needs the session has to run before the call that ends it. `LiveSessionTeardown`
//  forwards each one unchanged; nothing else implements it outside the tests.
//

import Foundation

protocol SessionTeardown {
    func unregisterDeviceToken(_ tokenHex: String) async throws
    func endLiveActivities() async
    func signOut() async throws
    func deleteAccount() async throws
    /// Forgets the game answers being sent right now (`GameResponseOutbox.reset()`).
    func resetGameResponseOutbox()
}

struct LiveSessionTeardown: SessionTeardown {
    func unregisterDeviceToken(_ tokenHex: String) async throws {
        try await BackendService.unregisterDeviceToken(tokenHex)
    }

    func endLiveActivities() async {
        await LiveActivityManager.shared.endAll()
    }

    func signOut() async throws {
        try await BackendService.signOut()
    }

    func deleteAccount() async throws {
        try await BackendService.deleteAccount()
    }

    func resetGameResponseOutbox() {
        GameResponseOutbox.reset()
    }
}
