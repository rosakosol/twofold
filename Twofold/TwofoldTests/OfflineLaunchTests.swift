//
//  OfflineLaunchTests.swift
//  TwofoldTests
//
//  What the app has to show for itself with no network.
//
//  `restoreSession` awaits a token refresh and then several more backend calls in sequence; offline
//  every one has to time out first, measured at ~45s on a cold launch. The cache is what stands in
//  for them, so what matters is that a snapshot written while online comes back intact — a launch
//  that reads nothing is a launch that shows a splash screen.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
struct OfflineLaunchTests {

    private let userID = UUID()

    private func record(
        active: Bool = true,
        tier: String? = "premium",
        userID: UUID,
        partnerConnected: Bool = true
    ) {
        OfflineSessionCache.record(
            active: active,
            tier: tier,
            userID: userID,
            partnerConnected: partnerConnected,
            myName: "Alex",
            partnerName: "Sam",
            celebrationShown: true,
            checklistDismissed: true
        )
    }

    // MARK: - What a launch with no network can read back

    @Test("everything the launch path needs survives the round trip")
    func snapshotRoundTrips() throws {
        OfflineSessionCache.clear()
        record(userID: userID)

        let restored = try #require(OfflineSessionCache.restore(for: userID), "nothing to launch from")
        #expect(restored.active)
        #expect(restored.tier == "premium")
        #expect(restored.partnerConnected, "otherwise an offline launch tells a paired couple to set up a partner")
        #expect(restored.myName == "Alex")
        #expect(restored.partnerName == "Sam")
        #expect(restored.celebrationShown, "one-time UI must not replay on every offline launch")
        #expect(restored.checklistDismissed)
        OfflineSessionCache.clear()
    }

    /// The reason this cache exists: `hasCouple` is set from being authenticated at all, but
    /// `isSubscriptionActive` only ever came from a backend read — so offline it kept its `false`
    /// default and a paying subscriber met the non-dismissable paywall.
    @Test("a subscriber stays a subscriber with the backend unreachable")
    func subscriptionSurvivesOffline() throws {
        OfflineSessionCache.clear()
        record(active: true, tier: "premium", userID: userID)
        #expect(OfflineSessionCache.restore(for: userID)?.active == true)
        OfflineSessionCache.clear()
    }

    // MARK: - What it must refuse to hand back

    /// Never let one account's entitlement leak into whoever signs in after them on the same
    /// device.
    @Test("a different account's cache is not used")
    func otherAccountsCacheIsIgnored() {
        OfflineSessionCache.clear()
        record(userID: userID)
        #expect(OfflineSessionCache.restore(for: UUID()) == nil)
        OfflineSessionCache.clear()
    }

    @Test("no signed-in user means nothing to restore")
    func noUserMeansNoSnapshot() {
        OfflineSessionCache.clear()
        record(userID: userID)
        #expect(OfflineSessionCache.restore(for: nil) == nil)
        OfflineSessionCache.clear()
    }

    /// Signing out has to take it with them, or the next person on this device inherits it.
    @Test("clearing leaves nothing behind")
    func clearingRemovesEverything() {
        record(userID: userID)
        OfflineSessionCache.clear()
        #expect(OfflineSessionCache.restore(for: userID) == nil)
    }

    /// "Stay offline forever" mustn't be an indefinite bypass — but the window is generous, since
    /// the app can't sync anything in that state anyway.
    @Test("a snapshot older than the window is refused")
    func staleSnapshotsExpire() {
        OfflineSessionCache.clear()
        record(userID: userID)
        // Wind the recorded time back past the 30-day ceiling.
        UserDefaults.standard.set(
            Date().timeIntervalSince1970 - (31 * 24 * 60 * 60),
            forKey: "offlineSession.recordedAt"
        )
        #expect(OfflineSessionCache.restore(for: userID) == nil)
        OfflineSessionCache.clear()
    }

    @Test("a device that has never been online has nothing, and says so")
    func firstEverLaunchHasNoCache() {
        OfflineSessionCache.clear()
        #expect(OfflineSessionCache.restore(for: userID) == nil)
    }
}

/// What the *data* cache has to carry for an offline Home to render at all.
///
/// Everything on that screen is built from the couple's home cities and avatars: the timezone card,
/// the distance, the globe, the header. Neither was cached, so a cold launch with no network fell
/// through to "add your home cities" — telling a long-paired couple to set up something they set up
/// long ago — and drew initials where two faces should be.
/// Serialized for the same reason  is: these all write and clear one shared
/// file, so run in parallel they clear each other's fixtures mid-test.
@Suite(.serialized)
struct OfflineHomeDataTests {

    private let userID = UUID()

    private func place(_ city: String, _ country: String) -> Place {
        Place(id: UUID(), city: city, country: country, iataCode: nil, latitude: 1, longitude: 2)
    }

    private func record(userID: UUID, myCity: Place?, partnerCity: Place?, myAvatar: URL?, partnerAvatar: URL?) {
        OfflineDataCache.record(
            trips: [], flights: [], memories: [],
            myCity: myCity, partnerCity: partnerCity,
            myAvatarURL: myAvatar, partnerAvatarURL: partnerAvatar,
            userID: userID
        )
    }

    @Test("both home cities survive, so the timezone card and globe have somewhere to draw")
    func citiesRoundTrip() throws {
        OfflineDataCache.clear()
        record(
            userID: userID,
            myCity: place("Rome", "Italy"),
            partnerCity: place("Fukuoka", "Japan"),
            myAvatar: nil, partnerAvatar: nil
        )
        let restored = try #require(OfflineDataCache.restore(for: userID))
        #expect(restored.myCity?.city == "Rome")
        #expect(restored.partnerCity?.city == "Fukuoka")
        OfflineDataCache.clear()
    }

    /// The signed token in a stored URL is stale by the time it's read back, and that's fine:
    /// `RemoteImageDiskCache` keys on the path, which doesn't change when the URL is re-signed.
    /// Without the URL at all there's no key to look up, which is why faces were missing even with
    /// the images already on disk.
    @Test("avatar URLs survive, so the disk cache has a key to look up")
    func avatarURLsRoundTrip() throws {
        OfflineDataCache.clear()
        let mine = URL(string: "https://example.com/storage/couple/me/avatar.jpg?token=abc")!
        let theirs = URL(string: "https://example.com/storage/couple/them/avatar.jpg?token=def")!
        record(userID: userID, myCity: nil, partnerCity: nil, myAvatar: mine, partnerAvatar: theirs)

        let restored = try #require(OfflineDataCache.restore(for: userID))
        #expect(restored.myAvatarURL?.path == mine.path, "the path is the part that has to survive")
        #expect(restored.partnerAvatarURL?.path == theirs.path)
        OfflineDataCache.clear()
    }

    @Test("a different account's home and faces are not restored")
    func accountScoped() {
        OfflineDataCache.clear()
        record(userID: userID, myCity: place("Rome", "Italy"), partnerCity: nil, myAvatar: nil, partnerAvatar: nil)
        #expect(OfflineDataCache.restore(for: UUID()) == nil)
        OfflineDataCache.clear()
    }
}
