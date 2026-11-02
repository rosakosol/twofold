//
//  BackendService+PushTokens.swift
//  Twofold
//
//  APNs device tokens.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Push device tokens

    /// Goes through the RPC rather than upserting `device_push_tokens` directly: a token already
    /// registered by a *different* account on this same device (someone signed out and signed in
    /// as someone else) can't be updated under the own-rows-only UPDATE policy, so the direct
    /// upsert failed with 42501 and the device quietly stopped getting pushes. The security-
    /// definer function reassigns it to the caller — see the migration's header for why that
    /// isn't just a looser policy. `profile_id` is taken from `auth.uid()` server-side, so
    /// there's nothing to pass but the token itself.
    static func registerDeviceToken(_ token: String, environment: String) async throws {
        guard currentUserID != nil else { throw BackendError.notAuthenticated }
        struct Params: Encodable {
            var pApnsToken: String
            var pEnvironment: String

            enum CodingKeys: String, CodingKey {
                case pApnsToken = "p_apns_token"
                case pEnvironment = "p_environment"
            }
        }
        try await supabase
            .rpc("register_device_push_token", params: Params(pApnsToken: token, pEnvironment: environment))
            .execute()
    }

    /// Called right before sign-out (while the session is still valid — `device_push_tokens`'
    /// own `delete_own` RLS policy requires `profile_id = auth.uid()`, which stops resolving the
    /// instant the session ends). Without this, the row stayed pointed at the signed-out account
    /// indefinitely, since nothing else ever removes it — this device kept receiving that
    /// account's push notifications (new trip/memory, flight updates, game turns...) even after
    /// the app itself showed signed out, until a *different* account happened to sign in on the
    /// same device and reassigned the row via `registerDeviceToken`'s own upsert.
    static func unregisterDeviceToken(_ token: String) async throws {
        guard currentUserID != nil else { return }
        try await supabase
            .from("device_push_tokens")
            .delete()
            .eq("apns_token", value: token)
            .execute()
    }
}
