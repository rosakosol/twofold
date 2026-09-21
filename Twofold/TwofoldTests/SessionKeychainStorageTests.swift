//
//  SessionKeychainStorageTests.swift
//  TwofoldTests
//
//  The refresh token moved to `ThisDeviceOnly` accessibility so it stops being backup-eligible.
//  The change itself is three lines; the reason it needed a file of its own is the migration.
//
//  Every user of every previous build has an item in the Keychain written by supabase-swift's
//  default storage at `kSecAttrAccessibleAfterFirstUnlock`. If the replacement does not find that
//  item — a different service name, a different account key, a delete-then-add that fails
//  halfway — then updating the app silently signs everybody out. That is the failure this file
//  exists to make impossible to ship, and the first test is the one that matters: an item written
//  the old way is still returned.
//

import Testing
import Foundation
import Security
@testable import Twofold

@Suite(.serialized)
struct SessionKeychainStorageTests {

    /// The account key is scoped to this test so a run cannot touch a real session that happens to
    /// be in the simulator's keychain.
    private static let key = "twofold.tests.session-storage"
    private static let service = "supabase.gotrue.swift"

    private func deleteRaw() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.key,
        ] as CFDictionary)
    }

    /// Writes an item exactly as the previous build's storage would have.
    private func seedLegacyItem(_ value: Data) {
        deleteRaw()
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ] as CFDictionary, nil)
        #expect(status == errSecSuccess, "precondition: could not seed a legacy item")
    }

    private func currentAccessibility() -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let attributes = item as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }

    // MARK: - The one that stops an update signing everybody out

    @Test("a session written by the previous build is still readable")
    func legacyItemIsFound() throws {
        let session = Data("refresh-token-from-the-old-build".utf8)
        seedLegacyItem(session)
        defer { deleteRaw() }

        let read = try SessionKeychainStorage().retrieve(key: Self.key)

        #expect(read == session, "if this is nil, updating the app signs every user out")
    }

    @Test("and reading it upgrades the accessibility in place")
    func readUpgradesAccessibility() throws {
        seedLegacyItem(Data("token".utf8))
        defer { deleteRaw() }
        #expect(currentAccessibility() == (kSecAttrAccessibleAfterFirstUnlock as String), "precondition")

        _ = try SessionKeychainStorage().retrieve(key: Self.key)

        #expect(
            currentAccessibility() == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
            "the item should no longer be backup-eligible"
        )
    }

    /// The upgrade must never be a delete-then-add: a failure between the two would be the thing
    /// this whole file is avoiding. Asserted by checking the data survives the upgrade.
    @Test("the upgrade preserves the token rather than replacing the item")
    func upgradeKeepsTheData() throws {
        let session = Data("must-survive".utf8)
        seedLegacyItem(session)
        defer { deleteRaw() }

        let storage = SessionKeychainStorage()
        _ = try storage.retrieve(key: Self.key)

        #expect(try storage.retrieve(key: Self.key) == session)
    }

    // MARK: - Ordinary behaviour

    @Test("a freshly stored session is written ThisDeviceOnly")
    func storeUsesThisDeviceOnly() throws {
        deleteRaw()
        defer { deleteRaw() }

        try SessionKeychainStorage().store(key: Self.key, value: Data("new".utf8))

        #expect(currentAccessibility() == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    }

    @Test("storing twice replaces rather than duplicating")
    func storeOverwrites() throws {
        deleteRaw()
        defer { deleteRaw() }
        let storage = SessionKeychainStorage()

        try storage.store(key: Self.key, value: Data("first".utf8))
        try storage.store(key: Self.key, value: Data("second".utf8))

        #expect(try storage.retrieve(key: Self.key) == Data("second".utf8))
    }

    @Test("a missing key reads as nil rather than throwing")
    func missingKeyIsNil() throws {
        deleteRaw()
        #expect(try SessionKeychainStorage().retrieve(key: Self.key) == nil)
    }

    @Test("removing is idempotent, because signing out can be retried")
    func removeIsIdempotent() throws {
        deleteRaw()
        let storage = SessionKeychainStorage()
        try storage.store(key: Self.key, value: Data("x".utf8))

        try storage.remove(key: Self.key)
        try storage.remove(key: Self.key)

        #expect(try storage.retrieve(key: Self.key) == nil)
    }
}
