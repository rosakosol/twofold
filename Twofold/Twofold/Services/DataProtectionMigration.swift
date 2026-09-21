//
//  DataProtectionMigration.swift
//  Twofold
//
//  A protection class on a write only classifies what is written from then on.
//
//  Everything already on disk keeps the class it was created under, which for every install
//  before this change is `CompleteUntilFirstUserAuthentication` — readable by any code in the
//  process from the first unlock after boot, and decryptable from an unencrypted backup. The
//  photo cache makes that concrete: `MemoryPhotoDiskCache.write` only runs for photos
//  `has(path:)` reports missing, so a couple who installed six months ago would keep 250 MB of
//  photographs at the old class indefinitely, and nothing would ever rewrite them.
//
//  Not a re-write. `setAttributes` rewraps the file's per-file key with the new class key and
//  never touches the bytes, so this costs milliseconds on a cache that would take minutes to
//  copy — and it does not need double the free space to do it.
//

import Foundation
import UIKit

enum DataProtectionMigration {
    /// Bump when a tree is added below, so the walk runs again for the new one.
    private static let currentVersion = 1
    private static let versionKey = "dataProtection.migratedVersion"

    static func runIfNeeded() {
        guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

        // Raising CUFUA to Complete needs the class-A key to rewrap against, and that key does not
        // exist while the device is locked — every `setAttributes` would fail. The app can be
        // launched into the background while locked, so this is a path that gets taken rather than
        // a theoretical one, and stamping the version there would mark work as done that never
        // happened. Wait for the unlock instead.
        guard UIApplication.shared.isProtectedDataAvailable else {
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: nil
            ) { _ in runIfNeeded() }
            return
        }

        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]

            // Named individually rather than walking Application Support, because PostHog and
            // RevenueCat keep their own files in that root. PostHog flushes its queue from a
            // background task, and sweeping it to Complete would break that for no benefit — its
            // contents are event names and onboarding traits, not couple content.
            for url in [
                support.appendingPathComponent("OfflineDataCache.json"),
                support.appendingPathComponent("OfflineGameStateCache.json"),
                support.appendingPathComponent("GameContent.json"),
                support.appendingPathComponent("PendingMemories", isDirectory: true),
                support.appendingPathComponent("PendingTrips", isDirectory: true),
                caches.appendingPathComponent("MemoryPhotos", isDirectory: true),
                caches.appendingPathComponent("RemoteImages", isDirectory: true),
            ] {
                apply(.complete, to: url)
            }

            // The app group stays at CompleteUntilFirstUserAuthentication on purpose — the widget
            // extension reads it on the Lock Screen, so Complete blanks it. See
            // `WidgetImageCache.protection`. Restated here so the class is a decision on the record
            // for files written before that constant existed, rather than whatever they inherited.
            if let group = fm.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.orangefinch.Twofold"
            ) {
                for name in [
                    "latest-memory.jpg",
                    "drawing-pad-last-good.png",
                    "my-drawing-pad-last-good.png",
                    "my-avatar.jpg",
                    "partner-avatar.jpg",
                    "airline-logo.png",
                ] {
                    apply(.completeUntilFirstUserAuthentication, to: group.appendingPathComponent(name))
                }
            }

            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }
    }

    /// Keeps a file out of the iCloud and iTunes backup.
    ///
    /// A separate lever from the protection class, and a commonly conflated one: a file at
    /// `.completeFileProtection` is backed up like any other, and an unencrypted backup is
    /// readable without the device passcode. So this is the only control over whether a file's
    /// contents leave the phone at all.
    ///
    /// Only for stores that can be re-derived. Anything that is the sole copy of something a
    /// person made — `PendingMemories`, `PendingTrips` — must stay in the backup, or restoring to
    /// a new phone loses a memory they drafted before pairing.
    ///
    /// Called after the write rather than when the URL is built, because `setResourceValues`
    /// needs the file to exist.
    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Sets `protection` on `url`, and on everything beneath it when `url` is a directory.
    ///
    /// Both halves are needed. `setAttributes` does not recurse, so the files have to be walked;
    /// and a directory carries a class of its own which is what a file created inside it without
    /// one inherits, so the directory has to be set too or the next write lands at the old class.
    private static func apply(_ protection: FileProtectionType, to url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        set(protection, at: url)
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileProtectionKey]) else { return }
        for case let child as URL in enumerator {
            set(protection, at: child)
        }
    }

    private static func set(_ protection: FileProtectionType, at url: URL) {
        // Reading the current class first is what makes a resumed run cheap: a walk interrupted by
        // the app being killed repeats the enumeration but not the rewraps.
        if let current = try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection,
           current.rawValue == protection.rawValue {
            return
        }
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
    }
}
