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
    private static let doodlePadFilename = "doodle-pad-last-good.png"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    static var latestMemoryImageURL: URL? {
        containerURL?.appendingPathComponent(latestMemoryFilename)
    }

    /// Overwrites in place — there's only ever one "latest memory" cached at a time.
    static func writeLatestMemoryImage(_ data: Data) {
        guard let url = latestMemoryImageURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readLatestMemoryImage() -> Data? {
        guard let url = latestMemoryImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func clearLatestMemoryImage() {
        guard let url = latestMemoryImageURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// DoodlePadWidget's own last-good fetch — written by the widget extension itself (the one
    /// widget allowed a network call, since the source bucket is public), so a stale/offline
    /// network still shows the last thing that loaded rather than a blank widget.
    static var doodlePadImageURL: URL? {
        containerURL?.appendingPathComponent(doodlePadFilename)
    }

    static func writeDoodlePadImage(_ data: Data) {
        guard let url = doodlePadImageURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readDoodlePadImage() -> Data? {
        guard let url = doodlePadImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// My own doodle-pad's last-good fetch — mirrors doodlePadImageURL (partner's), needed by
    /// DoodlePadWidget's Medium side-by-side layout, which shows both at once. Same "the widget
    /// fetches it live from the public bucket, this is just the offline/stale-network fallback"
    /// reasoning.
    private static let myDoodleFilename = "my-doodle-pad-last-good.png"

    static var myDoodleImageURL: URL? {
        containerURL?.appendingPathComponent(myDoodleFilename)
    }

    static func writeMyDoodleImage(_ data: Data) {
        guard let url = myDoodleImageURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readMyDoodleImage() -> Data? {
        guard let url = myDoodleImageURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Profile photos — public URLs (see Person.avatarURL's doc comment), downloaded and cached
    /// by the main app the same way the latest memory photo is, so avatar-bearing widgets
    /// (Days Together, Partner's Time, Flight Countdown, etc.) never need their own network call.
    private static let myAvatarFilename = "my-avatar.jpg"
    private static let partnerAvatarFilename = "partner-avatar.jpg"

    static func writeMyAvatarImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(myAvatarFilename) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readMyAvatarImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(myAvatarFilename) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func writePartnerAvatarImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(partnerAvatarFilename) else { return }
        try? data.write(to: url, options: .atomic)
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
        try? data.write(to: url, options: .atomic)
    }

    static func readAirlineLogoImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(airlineLogoFilename) else { return nil }
        return try? Data(contentsOf: url)
    }
}
