//
//  BackendService+Blocking.swift
//  Twofold
//
//  Blocking and unblocking people.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Blocking

    /// Blocks a profile, disconnecting them first if they are the current partner.
    ///
    /// Deliberately does not touch the shared archive: deleting that is the 90-day timer's job and
    /// nothing else's (20261005000000), and a block that also destroyed it would be the unilateral
    /// destruction that migration removed, wearing a safety label. See 20261023000000.
    static func blockProfile(_ profileID: UUID) async throws {
        struct Params: Encodable {
            var pProfileId: UUID
            enum CodingKeys: String, CodingKey { case pProfileId = "p_profile_id" }
        }
        try await supabase.rpc("block_profile", params: Params(pProfileId: profileID)).execute()
    }

    /// Somebody this account has blocked, as `list_blocked_profiles` returns them.
    struct BlockedProfile: Identifiable, Decodable, Equatable {
        var id: UUID
        var firstName: String
        var blockedAt: Date

        enum CodingKeys: String, CodingKey {
            case id = "profile_id"
            case firstName = "first_name"
            case blockedAt = "blocked_at"
        }
    }

    /// Everyone this account has blocked, newest first. A blocked person's profile is not readable
    /// directly, so this is the only way to name them (20261119000100).
    static func fetchBlockedProfiles() async throws -> [BlockedProfile] {
        try await supabase.rpc("list_blocked_profiles").execute().value
    }

    static func unblockProfile(_ profileID: UUID) async throws {
        struct Params: Encodable {
            var pProfileId: UUID
            enum CodingKeys: String, CodingKey { case pProfileId = "p_profile_id" }
        }
        try await supabase.rpc("unblock_profile", params: Params(pProfileId: profileID)).execute()
    }
}
