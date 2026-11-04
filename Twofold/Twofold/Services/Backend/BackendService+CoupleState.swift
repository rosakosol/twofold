//
//  BackendService+CoupleState.swift
//  Twofold
//
//  The whole couple in one load: both profiles, trips, flights and memories.
//

import Foundation
import Supabase

extension BackendService {

    /// Once paired, `couples.started_dating_on` (not `profiles.anniversary_date`) is the value
    /// `fetchCoupleState()` actually reads back — RLS blocks direct client writes to `couples`,
    /// so this goes through the same RPC pattern as `redeem_invite_code`/`leave_couple`.
    static func updateCoupleAnniversaryDate(coupleID: UUID, date: Date) async throws {
        struct Params: Encodable {
            var pCoupleId: UUID
            var pDate: String
            enum CodingKeys: String, CodingKey {
                case pCoupleId = "p_couple_id"
                case pDate = "p_date"
            }
        }
        try await supabase
            .rpc("update_couple_anniversary_date", params: Params(pCoupleId: coupleID, pDate: Self.dateOnlyFormatter.string(from: date)))
            .execute()
    }

    // MARK: - Couple state (couple + both profiles + trips + flights + memories)

    struct CoupleState {
        var couple: Couple
        var trips: [Trip]
        var memories: [Memory]
        /// Every flight for the couple — the authoritative list. Trip-linked flights are also
        /// grouped onto `trip.flights` for trip-scoped UI (a trip can have more than one leg).
        var flights: [Flight]
        /// "Your partner doesn't pay anything" — access is granted if *either* partner's
        /// device last reported an active local StoreKit entitlement.
        var subscriptionActive: Bool
        /// Whether *this* caller is the one paying, rather than either of them.
        ///
        /// `subscriptionActive` above is the OR, which is right for every access decision and
        /// wrong for anything addressed to the person: the delete-account screen was telling the
        /// non-paying partner to go and cancel a subscription that is not theirs and that they
        /// cannot see in their own Apple Account.
        var viewerSubscriptionActive: Bool
        /// The higher of the two partners' tiers ("premium" beats "plus") — nil only if neither
        /// has ever purchased since this column was added (pre-existing subscribers).
        var subscriptionTier: String?
        /// Where the *caller's own* subscription was bought, from `meProfile` — deliberately not
        /// the couple's, for the same reason `viewerSubscriptionActive` exists above. It answers
        /// "where do I go to change this", which is meaningless about the other partner's purchase.
        /// Only meaningful while `viewerSubscriptionActive` is true: like `subscription_tier`, the
        /// column is left stale rather than nulled when a subscription lapses.
        var viewerSubscriptionStore: String?
        /// Both of these are the *caller's own* flags (from `meProfile`, never the partner's) —
        /// each side dismisses their own copy of these one-time prompts independently.
        var partnerConnectedCelebrationShown: Bool
        var setupChecklistDismissed: Bool
    }

    static func fetchCoupleState() async throws -> CoupleState? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        guard let coupleRow = try await activeCoupleRow() else { return nil }

        // Four independent reads, started together rather than one after another.
        //
        // Each of them needs nothing but `coupleRow`, and they were simply `await`ed in source
        // order — so every launch paid four sequential round trips where it owed one. On a slow
        // connection that is most of a second before the app has anything to draw, and this is
        // the call that gates first paint for the whole couple.
        //
        // `archivedCoupleSummary`, sixty lines up, already fires its couple-scoped selects with
        // `async let`. This is that pattern applied to the path that actually matters.
        async let profileRowsTask: [ProfileRow] = supabase
            .from("profiles")
            .select()
            .in("id", values: [coupleRow.partnerAId, coupleRow.partnerBId])
            .execute()
            .value

        async let tripRowsTask: [TripRow] = supabase
            .from("trips")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        // Flights are couple-scoped directly (not joined through trips) — a flight can exist
        // with no trip link at all.
        async let flightRowsTask: [FlightRow] = supabase
            .from("flights")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        async let memoryRowsTask: [MemoryRow] = supabase
            .from("memories")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        let profileRows = try await profileRowsTask

        guard let partnerAProfile = profileRows.first(where: { $0.id == coupleRow.partnerAId }),
              let partnerBProfile = profileRows.first(where: { $0.id == coupleRow.partnerBId }) else {
            // The three reads still in flight are cancelled and awaited by `async let`'s own
            // scope exit, so returning here strands nothing.
            return nil
        }

        // The DB's partner_a_id/partner_b_id are just whichever two profiles happened to be
        // in the couples row — not necessarily "me first". Reorder here so the local model's
        // partnerA is always the signed-in user, since `AppModel.currentUser` assumes that.
        let meProfile = partnerAProfile.id == userID ? partnerAProfile : partnerBProfile
        let partnerProfile = partnerAProfile.id == userID ? partnerBProfile : partnerAProfile

        let tripRows = try await tripRowsTask
        let flightRows = try await flightRowsTask
        let memoryRows = try await memoryRowsTask

        // Second wave, also concurrent: the photo rows need the memory ids, and the places need
        // ids gathered from the profiles, the trips and the memories — but neither needs the
        // other, so they overlap too.
        async let memoryPhotoRowsTask: [MemoryPhotoRow] = {
            guard !memoryRows.isEmpty else { return [] }
            return try await supabase
                .from("memory_photos")
                .select()
                .in("memory_id", values: memoryRows.map(\.id))
                .order("position")
                .execute()
                .value
        }()

        var placeIDs = Set([partnerAProfile.homePlaceId, partnerBProfile.homePlaceId].compactMap { $0 })
        for row in tripRows { placeIDs.insert(row.originId); placeIDs.insert(row.destinationId) }
        for row in memoryRows { if let placeId = row.placeId { placeIDs.insert(placeId) } }
        let placeIDList = Array(placeIDs)
        async let placesTask = fetchPlaces(ids: placeIDList)

        let memoryPhotoRows = try await memoryPhotoRowsTask
        let places = try await placesTask

        // Both avatars signed together. `person(for:)` used to `await` the signing inside itself,
        // and the two calls building the couple below are arguments to the same initialiser — so
        // Swift evaluated them in order and my avatar's round trip finished before my partner's
        // began. Two independent files, two sequential requests, for no reason.
        async let myAvatarURL = avatarSignedURLOrNil(meProfile.avatarPath)
        // `partner_avatar_path` only — deliberately no fallback to the partner's own `avatar_path`.
        // This column is the photo *you* chose to represent your partner, and falling through to
        // theirs made a picture appear in a slot you never filled, indistinguishable from one you
        // had. An empty slot shows the usual initials placeholder, which is honest about there
        // being nothing set. `fetchOwnProfile` has always read this column alone; the two agree now.
        async let partnerAvatarURL = avatarSignedURLOrNil(meProfile.partnerAvatarPath)

        func person(for profile: ProfileRow, nameOverride: String?, avatarURL: URL?, paletteIndex: Int) -> Person {
            let name = (nameOverride?.isEmpty == false) ? nameOverride! : (profile.firstName.isEmpty ? "Partner" : profile.firstName)
            return Person(
                id: profile.id,
                name: name,
                homeCity: profile.homePlaceId.flatMap { places[$0] },
                accentColor: Person.palette[paletteIndex],
                avatarURL: avatarURL,
                // Read from whichever row this person is, so a partner's birthday is the one they
                // entered themselves. Unlike `nameOverride` above, there is nothing to override —
                // a birthday has one right answer and its owner is the only one who knows it.
                birthday: Birthday(month: profile.birthdayMonth, day: profile.birthdayDay),
                timeZoneIdentifier: profile.timezone
            )
        }

        let couple = Couple(
            id: coupleRow.id,
            // Nobody overrides how I see myself — my own name and avatar are always my own.
            partnerA: person(for: meProfile, nameOverride: nil, avatarURL: await myAvatarURL, paletteIndex: 1),
            // My partner, as *I* personally see them: a nickname if I've set one (independent
            // of whatever nickname, if any, they've set for me — each side's `partner_name`
            // lives on their own profile row), otherwise their real first name. Same idea for
            // the avatar — my own custom photo of them if I've set one, otherwise their own.
            // Home city is never overridden — that one's always shared/real once paired.
            partnerB: person(for: partnerProfile, nameOverride: meProfile.partnerName, avatarURL: await partnerAvatarURL, paletteIndex: 0),
            // Couple-level once paired (`redeem_invite_code` seeds it from whichever partner set
            // one during onboarding). Nil when neither did, which is no longer rare now the
            // anniversary can be skipped — and was never "today", which is what `.now` made it.
            startedDatingOn: coupleRow.startedDatingOn,
            connectedAt: coupleRow.createdAt,
            maxDistanceKm: coupleRow.maxDistanceKm
        )

        let flights = flightRows.map { Self.makeFlight(from: $0) }
        // A trip's real itinerary can be more than one tracked flight (e.g. a connecting journey
        // routed through a layover) — group by trip rather than keeping only the first match.
        let flightsByTrip = Dictionary(grouping: flights.filter { $0.tripID != nil }, by: { $0.tripID! })

        let trips = makeTrips(rows: tripRows, places: places, flightsByTrip: flightsByTrip)

        // One request for every photo in the couple's history — see `memoryPhotoSignedURLs`.
        //
        // Concurrency was already fixed here once, from N sequential round trips to N parallel
        // ones. Parallel N is still N: a couple with 200 memories averaging three photos opened
        // 600 connections, which queue against the client's connection limit and land on the
        // server all at once, and first paint waited for the slowest of them.
        let signedURLsByPath = await memoryPhotoSignedURLs(paths: memoryPhotoRows.map(\.photoPath))

        let memories = makeMemories(rows: memoryRows, photoRows: memoryPhotoRows, places: places, signedURLs: signedURLsByPath)

        let effectiveTier = Self.effectiveTier([meProfile, partnerProfile].map { ($0.subscriptionActive, $0.subscriptionTier) })

        return CoupleState(
            couple: couple,
            trips: trips,
            memories: memories,
            flights: flights,
            subscriptionActive: meProfile.subscriptionActive || partnerProfile.subscriptionActive,
            viewerSubscriptionActive: meProfile.subscriptionActive,
            subscriptionTier: effectiveTier,
            viewerSubscriptionStore: meProfile.subscriptionStore,
            partnerConnectedCelebrationShown: meProfile.partnerConnectedCelebrationShown,
            setupChecklistDismissed: meProfile.setupChecklistDismissed
        )
    }

    /// Best-effort — a failed update just means the persisted high-water-mark stays stale until
    /// the next opportunity, not something worth surfacing as an error to the caller (see
    /// `AppModel.performAdopt`, the one call site). `couples` has no direct client update
    /// policy, so this goes through a security-definer RPC that does the `GREATEST` comparison
    /// server-side rather than a client read-then-write, which could race across both partners'
    /// devices and silently drop the higher value.
    static func updateCoupleMaxDistance(coupleID: UUID, distanceKm: Double) async throws {
        struct Params: Encodable {
            var pCoupleId: UUID
            var pDistanceKm: Double
            enum CodingKeys: String, CodingKey {
                case pCoupleId = "p_couple_id"
                case pDistanceKm = "p_distance_km"
            }
        }
        try await supabase
            .rpc("update_couple_max_distance", params: Params(pCoupleId: coupleID, pDistanceKm: distanceKm))
            .execute()
    }
}
