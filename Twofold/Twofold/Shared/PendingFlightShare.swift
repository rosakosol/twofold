//
//  PendingFlightShare.swift
//  Twofold
//
//  Compiled into both the main app and the Share Extension target — this is the
//  hand-off mechanism between the two separate processes. The extension only ever
//  writes; the main app reads, parses, and clears.
//
//  ⚠️ Once the Share Extension target exists in Xcode, add this file to that
//  target's membership too (the project's synchronized-group mechanism doesn't
//  share files across targets automatically).
//

import Foundation

struct PendingFlightShare: Codable, Identifiable, Equatable {
    let id: UUID
    /// The shared email's subject line, when the host app exposes one.
    let subject: String?
    /// The shared email's body text (plain text, or HTML stripped to plain text).
    let bodyText: String?
    /// Text extracted from a PDF attachment (boarding pass, e-ticket) — only meant to be
    /// used as a fallback when `subject`/`bodyText` don't yield a flight.
    let pdfText: String?
    let capturedAt: Date

    init(id: UUID = UUID(), subject: String? = nil, bodyText: String? = nil, pdfText: String? = nil, capturedAt: Date = .now) {
        self.id = id
        self.subject = subject
        self.bodyText = bodyText
        self.pdfText = pdfText
        self.capturedAt = capturedAt
    }
}

enum PendingShareStore {
    /// Must match the App Group capability added to both the main app and the extension targets.
    private static let appGroupID = "group.com.orangefinch.Twofold"
    private static let key = "pendingFlightShares"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func all() -> [PendingFlightShare] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingFlightShare].self, from: data)) ?? []
    }

    static func add(_ share: PendingFlightShare) {
        save(all() + [share])
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    private static func save(_ shares: [PendingFlightShare]) {
        guard let data = try? JSONEncoder().encode(shares) else { return }
        defaults?.set(data, forKey: key)
    }
}
