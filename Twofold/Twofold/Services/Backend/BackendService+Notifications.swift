//
//  BackendService+Notifications.swift
//  Twofold
//
//  Couple-activity pushes and their preferences.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Couple-activity notifications (drawing/trip/memory/game — not flight-specific)

    enum CoupleNotificationEvent: String {
        case drawingSaved = "drawing_saved"
        case tripAdded = "trip_added"
        case memoryAdded = "memory_added"
        case gameStarted = "game_started"
        case gameResultsReady = "game_results_ready"
        case gamePartnerFinished = "game_partner_finished"
        case gameReminder = "game_reminder"
        /// A happy-birthday message, sent by a partner pressing Send on `HappyBirthdayView`.
        /// Unlike the rest of these it is not a side effect of some other action — it is the
        /// action, which is why `sendBirthdayWish` reports whether it landed.
        case birthdayWish = "birthday_wish"
    }

    /// Tells the caller's partner (if any) about something the caller just did — best-effort,
    /// never throws. Called right after a real, synced write succeeds (never for a
    /// pending/local-only trip or memory added before pairing), since notifying about
    /// something that doesn't exist in the partner's own view yet would be misleading.
    /// `sessionID`/`gameType` are only meaningful for `.gameReminder`/`.gameResultsReady`/
    /// `.gamePartnerFinished` — they ride along in the push payload so tapping the delivered
    /// notification can deep-link straight into that session (see `PushNotificationDelegate`)
    /// instead of just opening the app. `target: .self` redirects the push to the caller's own
    /// devices instead of the partner's — see the call site in `AppModel.addMemory` for why.
    enum NotifyTarget: String {
        case partner
        case selfDevice = "self"
    }

    /// `isDaily` is only meaningful for `.gameResultsReady`/`.gamePartnerFinished`, and only
    /// changes the wording: the Daily Question is the one session whose completion moves the
    /// couple's streak, and a push that calls it "a game" is describing the wrong stakes. The flag
    /// is sent rather than inferred from `gameType`, since a daily session is an ordinary
    /// `deep_conversations` session under the hood and nothing in the payload distinguishes it.
    static func notifyPartner(event: CoupleNotificationEvent, detail: String? = nil, sessionID: UUID? = nil, gameType: GameType? = nil, isDaily: Bool = false, target: NotifyTarget = .partner) async {
        var body: [String: Any] = ["eventType": event.rawValue]
        if let detail { body["detail"] = detail }
        if let sessionID { body["sessionId"] = sessionID.uuidString }
        if let gameType { body["gameType"] = gameType.rawValue }
        if isDaily { body["isDaily"] = true }
        if target != .partner { body["target"] = target.rawValue }

        _ = try? await EdgeFunctions.send("notify-couple-event", body: body)
    }

    /// The same call as `notifyPartner`, with the outcome kept rather than discarded.
    ///
    /// Every other couple notification is a side effect of something that already succeeded — the
    /// trip is saved whether or not the push lands, so swallowing the result is right there and
    /// telling somebody their trip "failed" would be a lie. A birthday message is the opposite:
    /// pressing Send *is* the action, and reporting success for a request that never left would
    /// leave someone believing they had said something they had not.
    ///
    /// Returns false for any non-2xx or transport error. Does not throw, because the caller has
    /// nothing useful to do with the distinction between them.
    static func sendBirthdayWish(message: String) async -> Bool {
        var body: [String: Any] = ["eventType": CoupleNotificationEvent.birthdayWish.rawValue]
        if !message.isEmpty { body["detail"] = message }
        return (try? await EdgeFunctions.send("notify-couple-event", body: body)) != nil
    }

    struct CoupleNotificationPreferences {
        var partnerDrawingSaved: Bool
        var partnerTripAdded: Bool
        var partnerMemoryAdded: Bool
        var partnerGameStarted: Bool
        var partnerGameResultsReady: Bool
        var partnerGamePartnerFinished: Bool
        /// Connect 4 only — the one event that fires repeatedly *within* a game rather
        /// than once, which is why it is not folded into `partnerGameStarted`.
        var partnerGameTurn: Bool
        var partnerGameReminder: Bool
        var dailyStreakReminder: Bool
        /// The separate "1 hour left" last-chance nudge (23:00 UTC) — distinct from
        /// `dailyStreakReminder`'s own end-of-day-ish (18:00 UTC) one, so either can be turned
        /// off independently. See `send-streak-reminders`'s `final` mode.
        var streakEndingReminder: Bool
        var partnerInviteReminder: Bool

        static let allEnabled = CoupleNotificationPreferences(
            partnerDrawingSaved: true, partnerTripAdded: true, partnerMemoryAdded: true,
            partnerGameStarted: true, partnerGameResultsReady: true, partnerGamePartnerFinished: true,
            partnerGameTurn: true,
            partnerGameReminder: true,
            dailyStreakReminder: true, streakEndingReminder: true, partnerInviteReminder: true
        )
    }

    private struct CoupleNotificationPreferencesRow: Codable {
        var profileId: UUID
        var partnerDrawingSaved: Bool
        var partnerTripAdded: Bool
        var partnerMemoryAdded: Bool
        var partnerGameStarted: Bool
        var partnerGameResultsReady: Bool
        var partnerGamePartnerFinished: Bool
        var partnerGameTurn: Bool
        var partnerGameReminder: Bool
        var dailyStreakReminder: Bool
        var streakEndingReminder: Bool
        var partnerInviteReminder: Bool

        enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
            case partnerDrawingSaved = "partner_drawing_saved"
            case partnerTripAdded = "partner_trip_added"
            case partnerMemoryAdded = "partner_memory_added"
            case partnerGameStarted = "partner_game_started"
            case partnerGameResultsReady = "partner_game_results_ready"
            case partnerGamePartnerFinished = "partner_game_partner_finished"
            case partnerGameTurn = "partner_game_turn"
            case partnerGameReminder = "partner_game_reminder"
            case dailyStreakReminder = "daily_streak_reminder"
            case streakEndingReminder = "streak_ending_reminder"
            case partnerInviteReminder = "partner_invite_reminder"
        }
    }

    /// No row yet means "everything on" — matches the table's own column defaults, same
    /// fallback `notify-couple-event` uses server-side.
    static func fetchCoupleNotificationPreferences() async throws -> CoupleNotificationPreferences {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [CoupleNotificationPreferencesRow] = try await supabase
            .from("notification_preferences")
            .select()
            .eq("profile_id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return .allEnabled }
        return CoupleNotificationPreferences(
            partnerDrawingSaved: row.partnerDrawingSaved,
            partnerTripAdded: row.partnerTripAdded,
            partnerMemoryAdded: row.partnerMemoryAdded,
            partnerGameStarted: row.partnerGameStarted,
            partnerGameResultsReady: row.partnerGameResultsReady,
            partnerGamePartnerFinished: row.partnerGamePartnerFinished,
            partnerGameTurn: row.partnerGameTurn,
            partnerGameReminder: row.partnerGameReminder,
            dailyStreakReminder: row.dailyStreakReminder,
            streakEndingReminder: row.streakEndingReminder,
            partnerInviteReminder: row.partnerInviteReminder
        )
    }

    static func upsertCoupleNotificationPreferences(_ prefs: CoupleNotificationPreferences) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let row = CoupleNotificationPreferencesRow(
            profileId: userID,
            partnerDrawingSaved: prefs.partnerDrawingSaved,
            partnerTripAdded: prefs.partnerTripAdded,
            partnerMemoryAdded: prefs.partnerMemoryAdded,
            partnerGameStarted: prefs.partnerGameStarted,
            partnerGameResultsReady: prefs.partnerGameResultsReady,
            partnerGamePartnerFinished: prefs.partnerGamePartnerFinished,
            partnerGameTurn: prefs.partnerGameTurn,
            partnerGameReminder: prefs.partnerGameReminder,
            dailyStreakReminder: prefs.dailyStreakReminder,
            streakEndingReminder: prefs.streakEndingReminder,
            partnerInviteReminder: prefs.partnerInviteReminder
        )
        try await supabase
            .from("notification_preferences")
            .upsert(row, onConflict: "profile_id")
            .execute()
    }
}
