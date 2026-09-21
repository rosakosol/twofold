//
//  SessionKeychainStorage.swift
//  Twofold
//
//  Where the Supabase refresh token lives, and how reachable it is.
//
//  supabase-swift's default `KeychainLocalStorage` writes at `kSecAttrAccessibleAfterFirstUnlock`
//  (Auth/Internal/Keychain.swift). Without the `ThisDeviceOnly` suffix, a Keychain item is
//  included in an encrypted backup **and restored onto a different device** — so anyone able to
//  restore a backup, which needs the backup password rather than the phone's passcode, ends up
//  holding a live session for the couple's account. The accessibility is not configurable through
//  `SupabaseClientOptions`, so the storage has to be supplied instead.
//
//  `AfterFirstUnlockThisDeviceOnly` keeps the semantics the SDK actually needs — the session must
//  be readable after a reboot, before the user has unlocked, for a background refresh — while
//  taking the item out of the backup entirely.
//
//  ---------------------------------------------------------------------------
//  Migrating without signing anybody out
//  ---------------------------------------------------------------------------
//
//  The service name is deliberately the same as the default's, `supabase.gotrue.swift`, so this
//  reads the item an earlier build wrote rather than starting empty. If it did not, every
//  signed-in user would be silently signed out by the update — which is the one failure this
//  whole file has to avoid, and the reason it is not a two-line change.
//
//  The upgrade then happens in place: `retrieve` notices an item whose accessibility is the old
//  one and rewrites just that attribute. It does not delete and re-add, and it ignores its own
//  failure. A failed upgrade leaves a working session at the old accessibility, which is merely
//  the status quo; a failed delete-then-add would leave no session at all. Of the two ways for
//  this to go wrong, only one is visible to the person holding the phone, and this cannot reach it.
//
//  `store` writes the new accessibility on every save, so even if the in-place upgrade never ran,
//  the first token refresh after updating would migrate the item anyway.
//

import Foundation
import Security
import Supabase

struct SessionKeychainStorage: AuthLocalStorage {
    /// Matches supabase-swift's default so an item written by an earlier build is found.
    private static let service = "supabase.gotrue.swift"

    /// `AfterFirstUnlock` so a background refresh can still read it after a reboot;
    /// `ThisDeviceOnly` so it is excluded from backups and cannot be restored elsewhere.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    struct KeychainError: Error {
        let status: OSStatus
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
    }

    func store(key: String, value: Data) throws {
        let update: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: Self.accessibility,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }

        var insert = baseQuery(key)
        insert[kSecValueData as String] = value
        insert[kSecAttrAccessible as String] = Self.accessibility
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }

        upgradeAccessibilityIfNeeded(key)
        return data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Rewrites an item written by an earlier build to the stricter accessibility.
    ///
    /// Attribute-only, via `SecItemUpdate` — the data is not touched and the item is never
    /// removed, so there is no window in which the session does not exist. Every failure is
    /// swallowed on purpose: the worst outcome is that the token keeps the accessibility it has
    /// had all along, and the next `store` will try again.
    private func upgradeAccessibilityIfNeeded(_ key: String) {
        var query = baseQuery(key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let current = attributes[kSecAttrAccessible as String] as? String,
              current != (Self.accessibility as String)
        else { return }

        _ = SecItemUpdate(
            baseQuery(key) as CFDictionary,
            [kSecAttrAccessible as String: Self.accessibility] as CFDictionary
        )
    }
}
