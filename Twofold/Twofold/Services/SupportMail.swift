//
//  SupportMail.swift
//  Twofold
//
//  Plain `mailto:` links, not an in-app MFMailComposeViewController sheet — this hands off to
//  whatever mail client the person actually uses (theirs, not necessarily Apple Mail), needs no
//  MessageUI import/entitlement, and degrades gracefully: if `UIApplication.shared.open` can't
//  find anything to open it (e.g. no mail client at all), `SupportMenuItems` below falls back to
//  an alert with the address to reach out to manually.
//

import Foundation

enum SupportMail {
    static let address = "feedback@twofoldapp.com.au"

    /// Prefills the reporter's own account id so a support reply doesn't have to start by asking
    /// for it — `context` is a short human-readable breadcrumb (e.g. "Deep Conversation — session
    /// 3F2A...") for whichever screen the report was opened from.
    static func reportProblemURL(userID: UUID, context: String) -> URL? {
        mailURL(
            subject: "Twofold Problem Report",
            body: "User ID: \(userID.uuidString)\nContext: \(context)\n\nPlease describe the problem:\n"
        )
    }

    static func feedbackURL() -> URL? {
        mailURL(subject: "Twofold Feedback", body: nil)
    }

    private static func mailURL(subject: String, body: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        var queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let body {
            queryItems.append(URLQueryItem(name: "body", value: body))
        }
        components.queryItems = queryItems
        return components.url
    }
}
