//
//  WidgetImageCache.swift
//  Twofold
//
//  Small binary assets that don't belong in the UserDefaults-backed WidgetSnapshot (JSON isn't
//  a great fit for image bytes) — currently just the latest memory's photo, since its real
//  source URL is a *signed* Supabase Storage URL that expires and can't be safely cached
//  long-term as a URL. The main app downloads and overwrites this file in place each time the
//  latest memory changes; the widget just reads whatever's here, with no network of its own.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import Foundation

enum WidgetImageCache {
    private static let suiteName = "group.com.orangefinch.Twofold"
    private static let latestMemoryFilename = "latest-memory.jpg"
    private static let drawingPadFilename = "drawing-pad-last-good.png"

    /// Deliberately NOT `.completeFileProtection`, and deliberately stated rather than inherited.
    ///
    /// Everything in this container is read by the widget extension, and some of it while the
    /// device is locked. `JourneyLockScreenView` reads the airline logo to render a Live Activity
    /// on the Lock Screen, and five widgets declare Lock Screen accessory families whose timeline
    /// providers read the snapshot — `DaysTogetherWidget`, `TripCountdownWidget`,
    /// `FlightCountdownWidget`, `DistanceWidget`, `DistanceCompactWidget`. `DrawingPadWidget` also
    /// *writes* here from `getTimeline`.
    ///
    /// At `.completeFileProtection` every one of those reads fails while the device is locked and
    /// the widget draws blank — and because each write below is a `try?`, nothing would appear in
    /// a log. The first report would come from a review. This is the strongest class that still
    /// works, which is why it is written down instead of left to the default: the next person to
    /// raise protection across the app should have to read this before changing it.
    ///
    /// The main app's own copies of these images are separate files in Caches, and those *are* at
    /// Complete — raising them blanks nothing.
    private static let protection: Data.WritingOptions = .completeFileProtectionUntilFirstUserAuthentication

    /// One place, so the class and the backup exclusion cannot drift apart across six call sites.
    ///
    /// Excluded from backup because every one of these is re-derived by `WidgetSnapshotWriter` on
    /// the next foreground — there is nothing here that only exists here, and a backup copy of
    /// both partners' faces and the latest memory photo buys nobody anything.
    private static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, protection])
        // Inlined rather than calling `DataProtectionMigration.excludeFromBackup`: this file is
        // compiled into the widget extension as well as the app, and that helper is not.
        var backupURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? backupURL.setResourceValues(values)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    static var latestMemoryImageURL: URL? {
        containerURL?.appendingPathComponent(latestMemoryFilename)
    }

    /// Overwrites in place — there's only ever one "latest memory" cached at a time.
    static func writeLatestMemoryImage(_ data: Data) {
        guard let url = latestMemoryImageURL else { return }
        Self.write(data, to: url)
    }

    static func readLatestMemoryImage() -> Data? {
        guard let url = latestMemoryImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func clearLatestMemoryImage() {
        guard let url = latestMemoryImageURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// DrawingPadWidget's own last-good fetch — written by the widget extension itself (the one
    /// widget allowed a network call, since the source bucket is public), so a stale/offline
    /// network still shows the last thing that loaded rather than a blank widget.
    static var drawingPadImageURL: URL? {
        containerURL?.appendingPathComponent(drawingPadFilename)
    }

    static func writeDrawingPadImage(_ data: Data) {
        guard let url = drawingPadImageURL else { return }
        Self.write(data, to: url)
    }

    static func readDrawingPadImage() -> Data? {
        guard let url = drawingPadImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// My own drawing pad's last-good fetch — mirrors drawingPadImageURL (partner's), needed by
    /// DrawingPadWidget's Medium side-by-side layout, which shows both at once. Same "the widget
    /// fetches it live from the public bucket, this is just the offline/stale-network fallback"
    /// reasoning.
    private static let myDrawingFilename = "my-drawing-pad-last-good.png"

    static var myDrawingImageURL: URL? {
        containerURL?.appendingPathComponent(myDrawingFilename)
    }

    static func writeMyDrawingImage(_ data: Data) {
        guard let url = myDrawingImageURL else { return }
        Self.write(data, to: url)
    }

    static func readMyDrawingImage() -> Data? {
        guard let url = myDrawingImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Profile photos — public URLs (see Person.avatarURL's doc comment), downloaded and cached
    /// by the main app the same way the latest memory photo is, so avatar-bearing widgets
    /// (Days Together, Partner's Time, Flight Countdown, etc.) never need their own network call.
    private static let myAvatarFilename = "my-avatar.jpg"
    private static let partnerAvatarFilename = "partner-avatar.jpg"

    static func writeMyAvatarImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(myAvatarFilename) else { return }
        Self.write(data, to: url)
    }

    static func readMyAvatarImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(myAvatarFilename) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func writePartnerAvatarImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(partnerAvatarFilename) else { return }
        Self.write(data, to: url)
    }

    static func readPartnerAvatarImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(partnerAvatarFilename) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The next flight's airline logo — overwritten each refresh (there's only ever one "next
    /// flight" at a time, same as latestMemoryImage).
    private static let airlineLogoFilename = "airline-logo.png"

    static func writeAirlineLogoImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(airlineLogoFilename) else { return }
        Self.write(data, to: url)
    }

    static func readAirlineLogoImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(airlineLogoFilename) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Called on sign-out — removes every cached image file from the shared App Group container
    /// (both avatars, the latest memory photo, both drawing pads, the airline logo) so widgets
    /// don't keep rendering the signed-out account's (and their partner's) photos after they've
    /// signed out, until a different account signs in and overwrites them.
    static func clearAll() {
        guard let containerURL else { return }
        for filename in [myAvatarFilename, partnerAvatarFilename, latestMemoryFilename, drawingPadFilename, myDrawingFilename, airlineLogoFilename] {
            try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(filename))
        }
    }
}
