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

    /// A file in the app group container rather than the group's `UserDefaults`.
    ///
    /// That suite's plist is also where `WidgetSnapshot` lives, and the widget reads the snapshot
    /// on the Lock Screen — which pins everything in that one file to
    /// CompleteUntilFirstUserAuthentication. Nothing reads *this* while locked: a share sheet
    /// cannot be opened on a locked device, and the main app reads it in the foreground. So it can
    /// be at Complete, and cfprefsd's plist was the one place it could never get there.
    ///
    /// What it holds is a shared booking confirmation — subject, body, and text scraped from an
    /// attached boarding pass, so a traveller's legal name, their record locator and their
    /// itinerary.
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("pending-flight-shares.json")
    }

    static func all() -> [PendingFlightShare] {
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            return (try? JSONDecoder().decode([PendingFlightShare].self, from: data)) ?? []
        }
        // One-time read-through of the old location, so a share captured just before the update is
        // not dropped. Migrated on first read rather than at launch because the share extension
        // reaches this too, and it has no launch of its own to hook.
        guard let data = defaults?.data(forKey: key) else { return [] }
        let migrated = (try? JSONDecoder().decode([PendingFlightShare].self, from: data)) ?? []
        if !migrated.isEmpty { save(migrated) }
        defaults?.removeObject(forKey: key)
        return migrated
    }

    static func add(_ share: PendingFlightShare) {
        save(all() + [share])
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    /// Drops the whole queue.
    ///
    /// Missing until now, and this was the only store of the sixteen without one — so
    /// `clearLocalSessionState()` could not have called it even if somebody had remembered to.
    /// A queued share is the text of a booking confirmation: subject, body, and whatever was
    /// scraped out of an attached boarding pass, which is a traveller's legal name, their record
    /// locator and their itinerary. `HomeView` reads the queue on every appearance with no user id
    /// anywhere in the record, so it was offered to whoever signed in next.
    static func clear() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        // The old key too: an install that never read the queue between updating and signing out
        // would otherwise still be holding one.
        defaults?.removeObject(forKey: key)
    }

    private static func save(_ shares: [PendingFlightShare]) {
        guard let fileURL, let data = try? JSONEncoder().encode(shares) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
