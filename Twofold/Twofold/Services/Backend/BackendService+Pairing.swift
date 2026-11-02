//
//  BackendService+Pairing.swift
//  Twofold
//
//  Invite codes, connection requests, and restoring an archive when a couple pairs again.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Couple pairing

    nonisolated struct CoupleRow: Decodable {
        var id: UUID
        var partnerAId: UUID
        var partnerBId: UUID
        var status: String
        var dissolvedAt: Date?
        var createdAt: Date
        /// `started_dating_on` is a bare Postgres `date` column ("2025-02-08", no time/zone) —
        /// decoding it straight to `Date` throws under the client's timestamp-with-time-zone
        /// strategy, the same reason `ProfileRow.anniversaryDate` is `String?` too. That throw
        /// previously went unnoticed since every couple's `started_dating_on` was null until the
        /// reconciliation migration started backfilling real values — a decode failure here
        /// fails `fetchCoupleState()` entirely, which `loadSignedInState()` silently swallows and
        /// falls back to the solo-profile path, making a fully paired couple look disconnected.
        var startedDatingOnRaw: String?
        var maxDistanceKm: Double?
        /// When this archive is permanently deleted — 90 days after it ended. Null while the
        /// couple is active.
        var scheduledPurgeAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, status
            case partnerAId = "partner_a_id"
            case partnerBId = "partner_b_id"
            case dissolvedAt = "dissolved_at"
            case startedDatingOnRaw = "started_dating_on"
            case createdAt = "created_at"
            case maxDistanceKm = "max_distance_km"
            case scheduledPurgeAt = "scheduled_purge_at"
        }

        @MainActor var startedDatingOn: Date? {
            startedDatingOnRaw.flatMap { BackendService.dateOnlyFormatter.date(from: $0) }
        }
    }

    private nonisolated struct InviteCodeRow: Decodable {
        var code: String
    }

    /// Fully random (no name baked in — see the migration's own header comment for why),
    /// generated server-side.
    static func createInviteCode() async throws -> String {
        let row: InviteCodeRow = try await supabase
            .rpc("create_invite_code")
            .single()
            .execute()
            .value
        return row.code
    }

    struct InviterInfo {
        var name: String
        var avatarURL: URL?
    }

    private struct InviterInfoRow: Decodable {
        var firstName: String
        var avatarPath: String?

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case avatarPath = "avatar_path"
        }
    }

    /// The invite code's real inviter name + avatar, looked up server-side rather than guessed
    /// from the code's own text (codes carry no name information at all now). Deliberately
    /// callable without an authenticated session — this is the one place it matters most
    /// (JoinInviteView, reached from a cold deep-link tap before any account exists) — see the
    /// migration's own header comment for the resulting per-code (not per-caller) rate limit.
    /// Nil if the code doesn't resolve to a still-pending, unexpired invite.
    static func inviterInfo(forCode code: String) async throws -> InviterInfo? {
        struct Params: Encodable {
            var pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        let rows: [InviterInfoRow] = try await supabase
            .rpc("get_invite_code_inviter_info", params: Params(pCode: code))
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return InviterInfo(name: row.firstName, avatarURL: await avatarSignedURLOrNil(row.avatarPath))
    }

    /// All three fields are optional because `redeem_invite_code` reports expected failures as data
    /// rather than raising: a rejected attempt comes back as a 200 with `errorMessage` set and the
    /// other two null. It has to work that way — raising aborted the RPC's transaction, which rolled
    /// back the rate limiter's own attempt-log write along with it, so the limiter never tripped.
    private nonisolated struct RedeemInviteCodeResult: Decodable {
        var id: UUID?
        var inviterId: UUID?
        var errorMessage: String?
        /// True when a tapped link connected the two of them there and then, rather than leaving
        /// a request for the inviter to accept. Defaulted so an older server that does not send
        /// it reads as the safer answer — a request that still needs accepting.
        var autoAccepted: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case id
            case inviterId = "inviter_id"
            case errorMessage = "error_message"
            case autoAccepted = "auto_accepted"
        }
    }

    /// How the invitee came by the code, and what happened as a result.
    enum InviteOrigin: String {
        /// They typed it, so it could have been seen by anyone — the inviter approves.
        case code
        /// They tapped a link the inviter sent them, which connects immediately. See migration
        /// 20261008000000, including what that trades away.
        case link
    }

    struct RedeemOutcome {
        var requestID: UUID
        /// Connected already. The "request sent, we'll let you know" screens do not apply.
        var connected: Bool
    }

    /// Redeeming a code no longer immediately creates a couple — it creates a pending
    /// connection request only the inviter can accept (`respondToConnectionRequest`), so a
    /// brute-forced or mistyped-by-someone-else code can't silently pair an attacker as the
    /// partner — unless `origin` is `.link`, which connects them outright (see migration
    /// 20261008000000). `RedeemOutcome.connected` says which happened, and the screens that talk
    /// about waiting are wrong when it is true.
    ///
    /// Notifies the inviter directly, baked in here rather than left to each of the several call
    /// sites so it cannot be forgotten from one of them — there's no couple yet to resolve a
    /// recipient through, unlike `notifyPartner`.
    @discardableResult
    static func redeemInviteCode(_ code: String, origin: InviteOrigin = .code) async throws -> RedeemOutcome {
        struct Params: Encodable {
            var pCode: String
            var pOrigin: String
            enum CodingKeys: String, CodingKey {
                case pCode = "p_code"
                case pOrigin = "p_origin"
            }
        }
        let row: RedeemInviteCodeResult = try await supabase
            .rpc("redeem_invite_code", params: Params(pCode: code, pOrigin: origin.rawValue))
            .single()
            .execute()
            .value
        // Rethrown rather than returned so every call site's existing `catch { errorMessage =
        // error.localizedDescription }` keeps showing the same wording it did when these were
        // Postgres exceptions.
        if let message = row.errorMessage {
            throw BackendError.requestFailed(message: message)
        }
        guard let requestID = row.id, let inviterID = row.inviterId else {
            throw BackendError.requestFailed(message: nil)
        }
        Analytics.capture(Analytics.Event.inviteRedeem)

        // Which of the two things actually happened decides what the inviter is told. Sending
        // "someone wants to connect" to a person who is already connected would ask them to do
        // something that is no longer possible — and being told at all is one of the two backstops
        // the auto-accept path deliberately keeps.
        let connected = row.autoAccepted ?? false
        Task {
            await notifyConnectionRequest(
                eventType: connected ? "connection_accepted" : "connection_requested",
                targetProfileId: inviterID
            )
        }
        return RedeemOutcome(requestID: requestID, connected: connected)
    }

    struct OutgoingConnectionRequest: Decodable {
        var id: UUID
        var inviterId: UUID
        var inviterFirstName: String
        var inviterAvatarPath: String?
        var createdAt: Date
        /// Resolved after decoding (see `fetchMyOutgoingConnectionRequest`) — signing a storage
        /// URL is async, so it can't happen inline in a computed property the way the old public-
        /// URL version did. Deliberately excluded from `CodingKeys` so decoding leaves it nil.
        var inviterAvatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case inviterId = "inviter_id"
            case inviterFirstName = "inviter_first_name"
            case inviterAvatarPath = "inviter_avatar_path"
            case createdAt = "created_at"
        }
    }

    /// My own outgoing request, if I have one still pending — lets `RootView` show "{inviter}
    /// needs to accept" instead of the forced re-subscribe paywall while it's still pending (a
    /// pending invitee has no subscription of their own yet, and forcing them to pay while
    /// waiting on someone else's decision makes no sense), and survives a relaunch rather than
    /// only being known right after redeeming. A direct `connection_requests` select can't get
    /// the inviter's name/avatar here (no RLS visibility into their profile pre-connection), so
    /// this goes through `fetch_my_outgoing_connection_request` instead — see its own comment.
    /// The inviter's avatar itself is readable via the `avatars_select_connection_request_party`
    /// storage policy, which grants exactly this pairing (requester viewing inviter, or vice
    /// versa) once a `connection_requests` row links them.
    static func fetchMyOutgoingConnectionRequest() async throws -> OutgoingConnectionRequest? {
        let rows: [OutgoingConnectionRequest] = try await supabase
            .rpc("fetch_my_outgoing_connection_request")
            .execute()
            .value
        guard var row = rows.first else { return nil }
        row.inviterAvatarURL = await avatarSignedURLOrNil(row.inviterAvatarPath)
        return row
    }

    /// A past relationship with this same person that could be brought back, if there is one.
    ///
    /// Nil when they have no shared past, or when its 90 days have run out — after that the data
    /// is gone and re-pairing simply starts fresh, which needs no prompt.
    struct RestorableArchive: Decodable {
        var coupleID: UUID
        var dissolvedAt: Date?
        var scheduledPurgeAt: Date?
        var memoryCount: Int
        var tripCount: Int
        var flightCount: Int

        enum CodingKeys: String, CodingKey {
            case coupleID = "couple_id"
            case dissolvedAt = "dissolved_at"
            case scheduledPurgeAt = "scheduled_purge_at"
            case memoryCount = "memory_count"
            case tripCount = "trip_count"
            case flightCount = "flight_count"
        }

        /// Nothing worth offering to bring back. An empty archive would make the prompt a question
        /// about nothing.
        var isEmpty: Bool { memoryCount == 0 && tripCount == 0 && flightCount == 0 }

        /// "12 memories, 3 trips and 2 flights" — only the parts that exist.
        var summary: String {
            var parts: [String] = []
            if memoryCount > 0 { parts.append("\(memoryCount) \(memoryCount == 1 ? "memory" : "memories")") }
            if tripCount > 0 { parts.append("\(tripCount) \(tripCount == 1 ? "trip" : "trips")") }
            if flightCount > 0 { parts.append("\(flightCount) \(flightCount == 1 ? "flight" : "flights")") }
            guard let last = parts.popLast() else { return "nothing" }
            return parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        }
    }

    static func restorableArchive(withPartner partnerID: UUID) async throws -> RestorableArchive? {
        struct Params: Encodable {
            var pPartnerId: UUID
            enum CodingKeys: String, CodingKey { case pPartnerId = "p_partner_id" }
        }
        let rows: [RestorableArchive] = try await supabase
            .rpc("restorable_archive_with", params: Params(pPartnerId: partnerID))
            .execute()
            .value
        return rows.first
    }

    struct PendingConnectionRequest: Identifiable, Decodable {
        var id: UUID
        var requesterId: UUID
        var requesterFirstName: String
        var requesterAvatarPath: String?
        var createdAt: Date
        /// Resolved after decoding, same reason/pattern as `OutgoingConnectionRequest.inviterAvatarURL`.
        var requesterAvatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case requesterId = "requester_id"
            case requesterFirstName = "requester_first_name"
            case requesterAvatarPath = "requester_avatar_path"
            case createdAt = "created_at"
        }
    }

    /// Incoming requests awaiting my decision (I'm the inviter on each of these). Avatars
    /// resolved concurrently, same pattern as memory photos in `fetchCoupleState`.
    static func fetchPendingConnectionRequests() async throws -> [PendingConnectionRequest] {
        let rows: [PendingConnectionRequest] = try await supabase.rpc("fetch_pending_connection_requests").execute().value
        return await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, row) in rows.enumerated() {
                group.addTask { (index, await avatarSignedURLOrNil(row.requesterAvatarPath)) }
            }
            var resolved = rows
            for await (index, url) in group {
                resolved[index].requesterAvatarURL = url
            }
            return resolved
        }
    }

    /// Accepts or declines an incoming request — only callable by the request's own inviter.
    /// Returns the newly created couple's id on accept, nil on decline. Notifies the original
    /// requester directly on accept (baked in here for the same reason `redeemInviteCode` bakes
    /// in its own notify call) — `row.partnerBId` is the requester, per the insert order
    /// `respond_to_connection_request` itself uses.
    /// `restoreArchive` brings a previous relationship with this same person back rather than
    /// starting a new one — every memory, photo, trip and flight as it was. Only possible at this
    /// moment: restoring reuses the old couple's id, which is what keeps the storage paths and
    /// foreign keys valid, and once a new couple row exists there is nothing to reuse. See
    /// migration 20261004000000.
    @discardableResult
    static func respondToConnectionRequest(id: UUID, accept: Bool, restoreArchive: Bool = false) async throws -> UUID? {
        struct Params: Encodable {
            var pRequestId: UUID
            var pAccept: Bool
            var pRestoreArchive: Bool
            enum CodingKeys: String, CodingKey {
                case pRequestId = "p_request_id"
                case pAccept = "p_accept"
                case pRestoreArchive = "p_restore_archive"
            }
        }
        let row: CoupleRow? = try await supabase
            .rpc("respond_to_connection_request",
                 params: Params(pRequestId: id, pAccept: accept, pRestoreArchive: restoreArchive))
            .execute()
            .value
        if let row {
            Task { await notifyConnectionRequest(eventType: "connection_accepted", targetProfileId: row.partnerBId) }
        }
        return row?.id
    }

    /// Shared by `redeemInviteCode`/`respondToConnectionRequest` — unlike `notifyPartner`,
    /// there's no couple to resolve a recipient through (that's the whole point pre-acceptance),
    /// so the target profile is passed explicitly.
    private static func notifyConnectionRequest(eventType: String, targetProfileId: UUID) async {
        let body: [String: Any] = ["eventType": eventType, "targetProfileId": targetProfileId.uuidString]
        _ = try? await EdgeFunctions.send("notify-connection-request", body: body)
    }

    private nonisolated struct ConnectionRequestRow: Decodable {
        var inviterId: UUID
        enum CodingKeys: String, CodingKey { case inviterId = "inviter_id" }
    }

    /// Nudges the inviter on a still-pending outgoing request — reachable from Home's pending-
    /// invite card instead of the old hard paywall dead-end. Rate-limited server-side (see the
    /// `send_connection_request_reminder` RPC's own cooldown check); its exception message is
    /// what surfaces to the user on a too-soon retry, same pattern `removePartner`/
    /// `respondToConnectionRequest` already use for RPC-rejection messaging.
    static func sendConnectionRequestReminder(requestID: UUID) async throws {
        struct Params: Encodable {
            var pRequestId: UUID
            enum CodingKeys: String, CodingKey { case pRequestId = "p_request_id" }
        }
        let row: ConnectionRequestRow = try await supabase
            .rpc("send_connection_request_reminder", params: Params(pRequestId: requestID))
            .single()
            .execute()
            .value
        Task { await notifyConnectionRequest(eventType: "connection_reminder", targetProfileId: row.inviterId) }
    }
}
