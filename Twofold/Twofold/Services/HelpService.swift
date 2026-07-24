//
//  HelpService.swift
//  Twofold
//
//  Backs the Settings > Help screens (SendFeedbackView, SupportView) — a true in-app "send"
//  (via the submit-help-message Edge Function, which relays through Amazon SES) rather than a
//  mailto: handoff. Unrelated to Services/SupportMail.swift, which is still used as-is for the
//  in-game "report a problem" menus (a narrower, session-scoped mailto flow).
//

import Foundation

/// Mirrors submit-help-message/index.ts's SUPPORT_CATEGORIES verbatim — no shared codegen
/// between the two, so keep both lists in sync by hand if this ever changes.
enum SupportRequestCategory: String, CaseIterable, Identifiable {
    case accountAndSubscription = "Account & Subscription"
    case bugReport = "Bug Report"
    case flightTracking = "Flight Tracking"
    case tripsAndMemories = "Trips & Memories"
    case featureRequest = "Feature Request"
    case other = "Other"

    var id: String { rawValue }
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

    static func submitFeedback(message: String, subject: String? = nil) async throws {
        try await submit(body: [
            "target": "feedback",
            "message": message,
            "subject": subject as Any? ?? NSNull(),
        ])
    }

    static func submitSupportRequest(category: SupportRequestCategory, message: String, subject: String? = nil) async throws {
        try await submit(body: [
            "target": "support",
            "category": category.rawValue,
            "message": message,
            "subject": subject as Any? ?? NSNull(),
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
