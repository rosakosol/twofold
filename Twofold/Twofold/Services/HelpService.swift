//
//  HelpService.swift
//  Twofold
//
//  Backs Settings > Help > Support — a true in-app "send" (via the submit-help-message Edge
//  Function, which relays through Zoho Mail's SMTP) rather than a mailto: handoff. This is now
//  the app's only contact path: the separate "Send Feedback" screen and the in-game mailto:
//  menus were folded into this one categorised form (see SupportRequestCategory's .feedback and
//  .gameIssue), so Services/SupportMail.swift is gone.
//

import Foundation

/// Mirrors submit-help-message/index.ts's SUPPORT_CATEGORIES verbatim — no shared codegen
/// between the two, so keep both lists in sync by hand if this ever changes.
enum SupportRequestCategory: String, CaseIterable, Identifiable {
    case accountAndSubscription = "Account & Subscription"
    case bugReport = "Bug Report"
    case flightTracking = "Flight Tracking"
    case tripsAndMemories = "Trips & Memories"
    case gameIssue = "Game Issue"
    case featureRequest = "Feature Request"
    case feedback = "Feedback"
    case other = "Other"

    var id: String { rawValue }
}

/// Attached automatically when the form was opened from a game screen's "Report a Problem", so a
/// report names the exact deck and card without the reporter having to describe them.
///
/// The IDs carry the weight here: a deck title can be renamed or duplicated, so `deckID` /
/// `contentID` are what actually pin a report to a row in the games admin tables. Everything
/// except `gameType` is optional — the results screen has no single "current" round, and
/// daily-activity sessions aren't deck-originated, so those fields are legitimately absent.
struct GameIssueContext {
    var gameType: String
    var gameTitle: String?
    var deckID: UUID?
    var content: String?
    var contentID: UUID?
    var roundNumber: Int?
    var sessionID: UUID?

    /// A short "Trivia Battle — Airport Chaos · round 3" line, shown in the form so the reporter
    /// can see what's being attached rather than it being sent invisibly.
    var summary: String {
        var parts = [gameType]
        if let gameTitle { parts.append(gameTitle) }
        var line = parts.joined(separator: " — ")
        if let roundNumber { line += " · round \(roundNumber)" }
        return line
    }

    var payload: [String: Any] {
        var dict: [String: Any] = ["gameType": gameType]
        if let gameTitle { dict["gameTitle"] = gameTitle }
        if let deckID { dict["deckID"] = deckID.uuidString }
        if let content { dict["content"] = content }
        if let contentID { dict["contentID"] = contentID.uuidString }
        if let roundNumber { dict["roundNumber"] = roundNumber }
        if let sessionID { dict["sessionID"] = sessionID.uuidString }
        return dict
    }
}

struct FAQEntry: Identifiable, Decodable {
    let id: UUID
    var category: String?
    var question: String
    var answer: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, category, question, answer
        case sortOrder = "sort_order"
    }
}

enum HelpServiceError: LocalizedError {
    case notAuthenticated
    case requestFailed(message: String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "You need to be signed in to do that."
        case .requestFailed(let message): message ?? "Couldn't send your message. Try again in a moment."
        }
    }
}

enum HelpService {
    private struct ErrorResponse: Decodable {
        var error: String?
    }

    /// Grouped by `category` (nil-category entries — none in the seed data, but the column
    /// allows it — sort under a nil key, last) preserving each row's own `sortOrder` within its
    /// group; groups themselves are ordered by their first entry's `sortOrder`.
    static func fetchFAQ() async throws -> [FAQEntry] {
        try await supabase
            .from("faq_entries")
            .select()
            .order("sort_order")
            .execute()
            .value
    }

    static func submitSupportRequest(
        category: SupportRequestCategory,
        message: String,
        subject: String? = nil,
        game: GameIssueContext? = nil
    ) async throws {
        try await submit(body: [
            "category": category.rawValue,
            "message": message,
            "subject": subject as Any? ?? NSNull(),
            "game": game?.payload as Any? ?? NSNull(),
        ])
    }

    private static func submit(body: [String: Any]) async throws {
        guard let accessToken = BackendService.currentAccessToken else { throw HelpServiceError.notAuthenticated }

        // Drop nil-valued keys (e.g. no subject supplied) rather than sending JSON `null` —
        // `[String: Any]` + JSONSerialization would otherwise need each optional resolved
        // explicitly first regardless, so this is done once, here, rather than at every call site.
        let cleanedBody = body.filter { !($0.value is NSNull) }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/submit-help-message"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: cleanedBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HelpServiceError.requestFailed(message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw HelpServiceError.requestFailed(message: message)
        }
    }
}
