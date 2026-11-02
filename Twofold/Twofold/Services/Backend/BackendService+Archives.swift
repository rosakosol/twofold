//
//  BackendService+Archives.swift
//  Twofold
//
//  Leaving a couple, and the archived couples it leaves behind.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Remove partner / archived data

    /// Dissolves the couple — doesn't delete anything. Trips/memories/flights/game sessions
    /// stay in place and remain readable (existing RLS has no active-status gate on their
    /// SELECT policies), just no longer the caller's *active* couple, so the app naturally
    /// stops surfacing them in normal views. Either partner can call this unilaterally.
    @discardableResult
    static func leaveCouple(coupleID: UUID) async throws -> UUID {
        struct Params: Encodable {
            var pCoupleId: UUID
            enum CodingKeys: String, CodingKey { case pCoupleId = "p_couple_id" }
        }
        let row: CoupleRow = try await supabase
            .rpc("leave_couple", params: Params(pCoupleId: coupleID))
            .single()
            .execute()
            .value
        return row.id
    }

    private struct CoupleIDParams: Encodable {
        var pCoupleId: UUID
        enum CodingKeys: String, CodingKey { case pCoupleId = "p_couple_id" }
    }

    /// Hides an archive from this person's own list, or brings it back. Destroys nothing and
    /// needs nobody else's agreement — it is entirely about one person's own view.
    static func setCoupleArchiveHidden(coupleID: UUID, hidden: Bool) async throws {
        struct Params: Encodable {
            var pCoupleId: UUID
            var pHidden: Bool
            enum CodingKeys: String, CodingKey {
                case pCoupleId = "p_couple_id"
                case pHidden = "p_hidden"
            }
        }
        try await supabase
            .rpc("set_couple_archive_hidden", params: Params(pCoupleId: coupleID, pHidden: hidden))
            .execute()
    }

    /// Whether this person has taken an archive off their own list. Nothing else: a shared
    /// archive is deleted when its 90 days are up, and there is no request, no agreement and no
    /// early route for either partner to influence.
    struct CoupleArchiveState: Decodable {
        var hidden: Bool
    }

    static func coupleArchiveState(coupleID: UUID) async throws -> CoupleArchiveState? {
        let rows: [CoupleArchiveState] = try await supabase
            .rpc("couple_archive_state", params: CoupleIDParams(pCoupleId: coupleID))
            .execute()
            .value
        return rows.first
    }

    /// Every couple the signed-in user has since dissolved, newest first — the source list for
    /// Settings' "Archived data" screen. `partnerName` is that couple's *other* member's current
    /// first name (profiles stay readable regardless of couple status, see
    /// `profiles_select_self_or_partner`).
    static func fetchArchivedCouples() async throws -> [ArchivedCouple] {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "dissolved")
            .order("dissolved_at", ascending: false)
            .execute()
            .value
        guard !coupleRows.isEmpty else { return [] }

        // Which of these this user has hidden from their own list. Fetched rather than filtered
        // server-side so the screen can still offer them back — a hide nothing can undo would be
        // a delete by another name.
        struct HiddenRow: Decodable {
            var coupleId: UUID
            enum CodingKeys: String, CodingKey { case coupleId = "couple_id" }
        }
        let hiddenRows: [HiddenRow] = (try? await supabase
            .from("couple_archive_preferences")
            .select("couple_id")
            .eq("profile_id", value: userID)
            .not("hidden_at", operator: .is, value: "null")
            .execute()
            .value) ?? []
        let hiddenIDs = Set(hiddenRows.map(\.coupleId))

        let partnerIDs = coupleRows.map { $0.partnerAId == userID ? $0.partnerBId : $0.partnerAId }
        let profileRows: [ProfileRow] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: partnerIDs)
            .execute()
            .value
        let namesByID = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id, $0.firstName.isEmpty ? "Partner" : $0.firstName) })

        return coupleRows.map { row in
            let partnerID = row.partnerAId == userID ? row.partnerBId : row.partnerAId
            return ArchivedCouple(
                id: row.id,
                partnerName: namesByID[partnerID] ?? "Partner",
                startedDatingOn: row.startedDatingOn,
                dissolvedAt: row.dissolvedAt,
                scheduledPurgeAt: row.scheduledPurgeAt,
                isHidden: hiddenIDs.contains(row.id)
            )
        }
    }

    /// Lightweight counts for the archive detail screen — fetches just `id` columns rather than
    /// full rows, since only the counts are shown.
    static func fetchArchivedCoupleSummary(coupleID: UUID) async throws -> ArchivedCoupleSummary {
        struct IDRow: Decodable { var id: UUID }

        async let tripRows: [IDRow] = supabase.from("trips").select("id").eq("couple_id", value: coupleID).execute().value
        async let memoryRows: [IDRow] = supabase.from("memories").select("id").eq("couple_id", value: coupleID).execute().value
        async let flightRows: [IDRow] = supabase.from("flights").select("id").eq("couple_id", value: coupleID).execute().value
        async let gameRows: [IDRow] = supabase.from("game_sessions").select("id").eq("couple_id", value: coupleID).execute().value

        let (trips, memories, flights, games) = try await (tripRows, memoryRows, flightRows, gameRows)
        return ArchivedCoupleSummary(tripCount: trips.count, memoryCount: memories.count, flightCount: flights.count, gameSessionCount: games.count)
    }
}
