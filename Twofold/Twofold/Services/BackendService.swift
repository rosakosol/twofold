//
//  BackendService.swift
//  Twofold
//
//  All auth + database access to Supabase lives here. Row structs mirror the DB schema
//  (snake_case columns via explicit CodingKeys) and are mapped to/from the app's existing
//  Person/Place/Couple/Trip/Flight model structs, which stay backend-agnostic.
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit
import CryptoKit

enum BackendError: LocalizedError {
    case notAuthenticated
    case placeLookupFailed
    case avatarURLFailed
    case providerNotConfigured

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "You need to be signed in."
        case .placeLookupFailed: "Couldn't resolve that city."
        case .avatarURLFailed: "Couldn't get a URL for that photo."
        case .providerNotConfigured: "This sign-in option isn't set up yet."
        }
    }
}

enum BackendService {

    // MARK: - Auth

    @discardableResult
    static func signUp(firstName: String, email: String, password: String) async throws -> Session {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["first_name": .string(firstName)]
        )
        if let session = response.session {
            return session
        }
        // Confirmations are disabled for this project, so a session should always come back
        // immediately; fall back to an explicit sign-in just in case that ever changes.
        return try await supabase.auth.signIn(email: email, password: password)
    }

    @discardableResult
    static func signIn(email: String, password: String) async throws -> Session {
        try await supabase.auth.signIn(email: email, password: password)
    }

    /// Native Sign in with Apple. `nonce` is the raw (unhashed) nonce that was hashed into the
    /// original Apple authorization request — Supabase re-hashes and compares it against the
    /// token's own nonce claim to guard against replay.
    @discardableResult
    static func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    /// The ID token's `aud` claim matches whatever client ID *initiated* the sign-in request —
    /// which defaults to the iOS client (`GIDClientID` in Info.plist) unless a `serverClientID`
    /// is set. Supabase's Google provider is configured with the *Web* client (in the Supabase
    /// dashboard), so it rejects tokens audienced for the iOS client with "Unacceptable
    /// audience". Setting `serverClientID` here to that same Web client makes Google issue the
    /// token audienced correctly. See https://developers.google.com/identity/sign-in/ios/backend-auth.
    private static let googleWebClientID = "220566699855-1muier0anui8403ebqd5lpg3g288hima.apps.googleusercontent.com"

    /// Native Google Sign-In. `GIDClientID` (the iOS OAuth client) is read from Info.plist by
    /// the SDK automatically as the base configuration; `googleWebClientID` above is layered on
    /// as the `serverClientID` so Supabase can validate the resulting token.
    @discardableResult
    static func signInWithGoogle() async throws -> UUID {
        guard let presenter = topmostViewController() else { throw BackendError.notAuthenticated }
        guard let iosClientID = GIDSignIn.sharedInstance.configuration?.clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw BackendError.providerNotConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: iosClientID, serverClientID: googleWebClientID)

        // Unlike Sign in with Apple's SDK, GIDSignIn embeds whatever nonce it's given verbatim
        // into the ID token's `nonce` claim rather than hashing it first — so *we* need to hash
        // it before handing it to Google, then give Supabase the raw value so its own hash of
        // that matches the token's claim. Passing the same raw nonce to both (the previous bug
        // here) meant Supabase's hash of it could never equal the token's unhashed claim.
        let nonce = UUID().uuidString
        let hashedNonce = Self.sha256Hex(nonce)

        let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: hashedNonce) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let signInResult {
                    continuation.resume(returning: signInResult)
                } else {
                    continuation.resume(throwing: BackendError.notAuthenticated)
                }
            }
        }

        guard let idToken = result.user.idToken?.tokenString else { throw BackendError.notAuthenticated }

        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                nonce: nonce
            )
        )
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        return userID
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func topmostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private struct FirstNameUpdate: Encodable {
        var firstName: String
        enum CodingKeys: String, CodingKey { case firstName = "first_name" }
    }

    static func updateFirstName(_ name: String) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(FirstNameUpdate(firstName: name))
            .eq("id", value: userID)
            .execute()
    }

    static var currentUserID: UUID? {
        supabase.auth.currentSession?.user.id
    }

    /// Restores a persisted session (if any) on launch. supabase-swift keeps the refresh
    /// token in the Keychain, so this succeeds silently across app relaunches.
    static func restoreSession() async -> Session? {
        try? await supabase.auth.session
    }

    static func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// The signed-in user's own profile — used when they're authenticated but not (yet)
    /// paired with a partner, so `AppModel` can show their real name/photo/city instead of
    /// routing them back through onboarding just because no `couples` row exists yet.
    static func fetchOwnProfile() async throws -> Person? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [ProfileRow] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let profile = rows.first else { return nil }

        var homeCity: Place?
        if let placeID = profile.homePlaceId {
            homeCity = try await fetchPlaces(ids: [placeID])[placeID]
        }

        return Person(
            id: profile.id,
            name: profile.firstName.isEmpty ? "You" : profile.firstName,
            homeCity: homeCity,
            accentColor: Person.palette[1],
            avatarURL: profile.avatarPath.flatMap { avatarPublicURL(path: $0) }
        )
    }

    // MARK: - Places

    private struct PlaceRow: Decodable {
        var id: UUID
        var city: String
        var country: String
        var iataCode: String?
        var latitude: Double
        var longitude: Double
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case id, city, country, latitude, longitude, timezone
            case iataCode = "iata_code"
        }

        func toPlace() -> Place {
            Place(id: id, city: city, country: country, iataCode: iataCode, latitude: latitude, longitude: longitude, timeZoneIdentifier: timezone)
        }
    }

    private struct PlaceInsert: Encodable {
        var city: String
        var country: String
        var iataCode: String?
        var latitude: Double
        var longitude: Double
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case city, country, latitude, longitude, timezone
            case iataCode = "iata_code"
        }
    }

    private struct IDRow: Decodable {
        var id: UUID
    }

    /// Looks up a place by (city, country) — the table's unique constraint — inserting it
    /// if it isn't seeded yet. Returns the backend's row id, which almost never matches the
    /// id on the local `Place` struct (that one's just a client-side placeholder).
    static func findOrCreatePlaceID(_ place: Place) async throws -> UUID {
        let existing: [IDRow] = try await supabase
            .from("places")
            .select("id")
            .eq("city", value: place.city)
            .eq("country", value: place.country)
            .limit(1)
            .execute()
            .value

        if let id = existing.first?.id {
            return id
        }

        let insert = PlaceInsert(
            city: place.city,
            country: place.country,
            iataCode: place.iataCode,
            latitude: place.latitude,
            longitude: place.longitude,
            timezone: place.timeZoneIdentifier
        )
        let inserted: PlaceRow = try await supabase
            .from("places")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
        return inserted.id
    }

    static func fetchPlaces(ids: [UUID]) async throws -> [UUID: Place] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let rows: [PlaceRow] = try await supabase
            .from("places")
            .select()
            .in("id", values: unique)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.toPlace()) })
    }

    // MARK: - Profile / home city

    private struct ProfileRow: Decodable {
        var id: UUID
        var firstName: String
        var homePlaceId: UUID?
        var avatarPath: String?
        var partnerAvatarPath: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case homePlaceId = "home_place_id"
            case avatarPath = "avatar_path"
            case partnerAvatarPath = "partner_avatar_path"
        }
    }

    private struct HomeCityUpdate: Encodable {
        var homePlaceId: UUID
        enum CodingKeys: String, CodingKey { case homePlaceId = "home_place_id" }
    }

    /// Updates the signed-in user's own home city. RLS only allows updating your own
    /// profile row, so this can never be used to set a partner's city on their behalf.
    static func updateHomeCity(_ place: Place) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let placeID = try await findOrCreatePlaceID(place)
        try await supabase
            .from("profiles")
            .update(HomeCityUpdate(homePlaceId: placeID))
            .eq("id", value: userID)
            .execute()
    }

    private struct AnniversaryDateUpdate: Encodable {
        var anniversaryDate: String
        enum CodingKeys: String, CodingKey { case anniversaryDate = "anniversary_date" }
    }

    /// Stored on `profiles` (like `home_place_id`) rather than `couples.started_dating_on` —
    /// collected during onboarding, before a real couple exists yet.
    static func updateAnniversaryDate(_ date: Date) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(AnniversaryDateUpdate(anniversaryDate: Self.dateOnlyFormatter.string(from: date)))
            .eq("id", value: userID)
            .execute()
    }

    // MARK: - Avatar

    private struct AvatarPathUpdate: Encodable {
        var avatarPath: String
        enum CodingKeys: String, CodingKey { case avatarPath = "avatar_path" }
    }

    private struct PartnerAvatarPathUpdate: Encodable {
        var partnerAvatarPath: String
        enum CodingKeys: String, CodingKey { case partnerAvatarPath = "partner_avatar_path" }
    }

    static func avatarPublicURL(path: String) -> URL? {
        try? supabase.storage.from("avatars").getPublicURL(path: path)
    }

    /// Uploads the signed-in user's profile photo (JPEG data), points their profile at it,
    /// and returns the public URL for immediate local use.
    @discardableResult
    static func uploadAvatar(imageData: Data) async throws -> URL {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let path = "\(userID)/avatar.jpg"

        try await supabase.storage.from("avatars").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )

        try await supabase
            .from("profiles")
            .update(AvatarPathUpdate(avatarPath: path))
            .eq("id", value: userID)
            .execute()

        guard let url = avatarPublicURL(path: path) else { throw BackendError.avatarURLFailed }
        return url
    }

    /// Uploads *the signed-in user's own custom photo of their partner* — how they personally
    /// picture their partner, independent of whatever avatar the partner picked for themself.
    /// Stored under the signed-in user's own storage folder (not the partner's), so existing
    /// `avatars_*` policies already cover it.
    @discardableResult
    static func uploadPartnerAvatar(imageData: Data) async throws -> URL {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let path = "\(userID)/partner-avatar.jpg"

        try await supabase.storage.from("avatars").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )

        try await supabase
            .from("profiles")
            .update(PartnerAvatarPathUpdate(partnerAvatarPath: path))
            .eq("id", value: userID)
            .execute()

        guard let url = avatarPublicURL(path: path) else { throw BackendError.avatarURLFailed }
        return url
    }

    // MARK: - Couple pairing

    private struct CoupleRow: Decodable {
        var id: UUID
        var partnerAId: UUID
        var partnerBId: UUID
        var status: String

        enum CodingKeys: String, CodingKey {
            case id, status
            case partnerAId = "partner_a_id"
            case partnerBId = "partner_b_id"
        }
    }

    private struct InviteCodeRow: Decodable {
        var code: String
    }

    static func createInviteCode(firstName: String) async throws -> String {
        struct Params: Encodable {
            var pFirstName: String
            enum CodingKeys: String, CodingKey { case pFirstName = "p_first_name" }
        }
        let row: InviteCodeRow = try await supabase
            .rpc("create_invite_code", params: Params(pFirstName: firstName))
            .single()
            .execute()
            .value
        return row.code
    }

    @discardableResult
    static func redeemInviteCode(_ code: String) async throws -> UUID {
        struct Params: Encodable {
            var pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        let row: CoupleRow = try await supabase
            .rpc("redeem_invite_code", params: Params(pCode: code))
            .single()
            .execute()
            .value
        return row.id
    }

    // MARK: - Couple state (couple + both profiles + trips + flights + memories)

    struct CoupleState {
        var couple: Couple
        var trips: [Trip]
        var memories: [Memory]
    }

    static func fetchCoupleState() async throws -> CoupleState? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        guard let coupleRow = coupleRows.first else { return nil }

        let profileRows: [ProfileRow] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: [coupleRow.partnerAId, coupleRow.partnerBId])
            .execute()
            .value

        guard let partnerAProfile = profileRows.first(where: { $0.id == coupleRow.partnerAId }),
              let partnerBProfile = profileRows.first(where: { $0.id == coupleRow.partnerBId }) else {
            return nil
        }

        // The DB's partner_a_id/partner_b_id are just whichever two profiles happened to be
        // in the couples row — not necessarily "me first". Reorder here so the local model's
        // partnerA is always the signed-in user, since `AppModel.currentUser` assumes that.
        let meProfile = partnerAProfile.id == userID ? partnerAProfile : partnerBProfile
        let partnerProfile = partnerAProfile.id == userID ? partnerBProfile : partnerAProfile

        let tripRows: [TripRow] = try await supabase
            .from("trips")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        let flightRows: [FlightRow]
        if tripRows.isEmpty {
            flightRows = []
        } else {
            flightRows = try await supabase
                .from("flights")
                .select()
                .in("trip_id", values: tripRows.map(\.id))
                .execute()
                .value
        }

        let memoryRows: [MemoryRow] = try await supabase
            .from("memories")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        var placeIDs = Set([partnerAProfile.homePlaceId, partnerBProfile.homePlaceId].compactMap { $0 })
        for row in tripRows { placeIDs.insert(row.originId); placeIDs.insert(row.destinationId) }
        for row in flightRows { placeIDs.insert(row.originId); placeIDs.insert(row.destinationId) }
        for row in memoryRows { placeIDs.insert(row.placeId) }
        let places = try await fetchPlaces(ids: Array(placeIDs))

        func person(for profile: ProfileRow, avatarOverridePath: String?, paletteIndex: Int) -> Person {
            let avatarPath = avatarOverridePath ?? profile.avatarPath
            return Person(
                id: profile.id,
                name: profile.firstName.isEmpty ? "Partner" : profile.firstName,
                homeCity: profile.homePlaceId.flatMap { places[$0] },
                accentColor: Person.palette[paletteIndex],
                avatarURL: avatarPath.flatMap { avatarPublicURL(path: $0) }
            )
        }

        let couple = Couple(
            id: coupleRow.id,
            // My own avatar is always my own choice — nobody overrides how I see myself.
            partnerA: person(for: meProfile, avatarOverridePath: nil, paletteIndex: 1),
            // My partner's avatar, as *I* see them: my own custom pick if I've set one,
            // otherwise whatever photo they picked for themselves.
            partnerB: person(for: partnerProfile, avatarOverridePath: meProfile.partnerAvatarPath, paletteIndex: 0),
            startedDatingOn: .now
        )

        let flightsByTrip = Dictionary(uniqueKeysWithValues: flightRows.map { ($0.tripId, $0) })

        let trips: [Trip] = tripRows.compactMap { row in
            guard let origin = places[row.originId],
                  let destination = places[row.destinationId],
                  let category = TripCategory(dbValue: row.category) else { return nil }

            var trip = Trip(
                id: row.id,
                travelerID: row.travelerId,
                origin: origin,
                destination: destination,
                departureDate: row.departureAt,
                arrivalDate: row.arrivalAt,
                category: category,
                distanceKm: row.distanceKm,
                notes: row.notes
            )
            if let flightRow = flightsByTrip[row.id],
               let flightOrigin = places[flightRow.originId],
               let flightDestination = places[flightRow.destinationId] {
                trip.flight = Self.makeFlight(from: flightRow, origin: flightOrigin, destination: flightDestination)
            }
            return trip
        }

        var memories: [Memory] = []
        for row in memoryRows {
            guard let place = places[row.placeId] else { continue }
            var photoURL: URL?
            if let photoPath = row.photoPath {
                photoURL = try? await memoryPhotoSignedURL(path: photoPath)
            }
            memories.append(
                Memory(
                    id: row.id,
                    title: row.title,
                    emoji: row.emoji,
                    place: place,
                    date: row.occurredOnDate ?? .now,
                    note: row.note,
                    photoURL: photoURL
                )
            )
        }

        return CoupleState(couple: couple, trips: trips, memories: memories)
    }

    // MARK: - Trips / flights

    private struct TripRow: Decodable {
        var id: UUID
        var travelerId: UUID
        var originId: UUID
        var destinationId: UUID
        var departureAt: Date
        var arrivalAt: Date
        var category: String
        var distanceKm: Double
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case id, category, notes
            case travelerId = "traveler_id"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    private struct TripInsert: Encodable {
        var id: UUID
        var coupleId: UUID
        var travelerId: UUID
        var originId: UUID
        var destinationId: UUID
        var departureAt: Date
        var arrivalAt: Date
        var category: String
        var distanceKm: Double

        enum CodingKeys: String, CodingKey {
            case id, category
            case coupleId = "couple_id"
            case travelerId = "traveler_id"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    private struct FlightRow: Decodable {
        var id: UUID
        var tripId: UUID
        var flightNumber: String
        var originId: UUID
        var destinationId: UUID
        var scheduledDeparture: Date
        var scheduledArrival: Date

        enum CodingKeys: String, CodingKey {
            case id
            case tripId = "trip_id"
            case flightNumber = "flight_number"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case scheduledDeparture = "scheduled_departure"
            case scheduledArrival = "scheduled_arrival"
        }
    }

    private struct FlightInsert: Encodable {
        var tripId: UUID
        var flightNumber: String
        var originId: UUID
        var destinationId: UUID
        var scheduledDeparture: Date
        var scheduledArrival: Date

        enum CodingKeys: String, CodingKey {
            case tripId = "trip_id"
            case flightNumber = "flight_number"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case scheduledDeparture = "scheduled_departure"
            case scheduledArrival = "scheduled_arrival"
        }
    }

    /// `status`/`progress`/`timeline` are always derived client-side from now vs.
    /// scheduled departure/arrival — see `Flight`'s own computed properties — so the row
    /// only carries schedule + identity.
    private static func makeFlight(from row: FlightRow, origin: Place, destination: Place) -> Flight {
        Flight(
            id: row.id,
            flightNumber: row.flightNumber,
            origin: origin,
            destination: destination,
            status: .scheduled,
            scheduledDeparture: row.scheduledDeparture,
            scheduledArrival: row.scheduledArrival,
            progress: 0,
            timeline: []
        )
    }

    /// Inserts a trip (and its flight, if it has one) using the client-generated ids already
    /// on `trip`/`trip.flight`, resolving origin/destination against the `places` table.
    static func insertTrip(coupleID: UUID, trip: Trip) async throws {
        let originID = try await findOrCreatePlaceID(trip.origin)
        let destinationID = try await findOrCreatePlaceID(trip.destination)

        try await supabase
            .from("trips")
            .insert(
                TripInsert(
                    id: trip.id,
                    coupleId: coupleID,
                    travelerId: trip.travelerID,
                    originId: originID,
                    destinationId: destinationID,
                    departureAt: trip.departureDate,
                    arrivalAt: trip.arrivalDate,
                    category: trip.category.dbValue,
                    distanceKm: trip.distanceKm
                )
            )
            .execute()

        if let flight = trip.flight {
            try await insertFlight(tripID: trip.id, flight: flight, originID: originID, destinationID: destinationID)
        }
    }

    static func insertFlight(tripID: UUID, flight: Flight, originID: UUID? = nil, destinationID: UUID? = nil) async throws {
        let resolvedOriginID: UUID
        if let originID {
            resolvedOriginID = originID
        } else {
            resolvedOriginID = try await findOrCreatePlaceID(flight.origin)
        }
        let resolvedDestinationID: UUID
        if let destinationID {
            resolvedDestinationID = destinationID
        } else {
            resolvedDestinationID = try await findOrCreatePlaceID(flight.destination)
        }

        try await supabase
            .from("flights")
            .insert(
                FlightInsert(
                    tripId: tripID,
                    flightNumber: flight.flightNumber,
                    originId: resolvedOriginID,
                    destinationId: resolvedDestinationID,
                    scheduledDeparture: flight.scheduledDeparture,
                    scheduledArrival: flight.scheduledArrival
                )
            )
            .execute()
    }

    // MARK: - Flight updates (self-reported)

    private struct FlightUpdateRow: Decodable {
        var id: UUID
        var kind: FlightUpdateKind
        var note: String?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, kind, note
            case createdAt = "created_at"
        }
    }

    private struct FlightUpdateInsert: Encodable {
        var flightId: UUID
        var kind: FlightUpdateKind
        var note: String?
        var createdBy: UUID

        enum CodingKeys: String, CodingKey {
            case kind, note
            case flightId = "flight_id"
            case createdBy = "created_by"
        }
    }

    static func fetchFlightUpdates(flightID: UUID) async throws -> [FlightUpdate] {
        let rows: [FlightUpdateRow] = try await supabase
            .from("flight_updates")
            .select()
            .eq("flight_id", value: flightID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { FlightUpdate(id: $0.id, kind: $0.kind, note: $0.note, createdAt: $0.createdAt) }
    }

    static func insertFlightUpdate(flightID: UUID, kind: FlightUpdateKind, note: String?) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("flight_updates")
            .insert(FlightUpdateInsert(flightId: flightID, kind: kind, note: note, createdBy: userID))
            .execute()
    }

    /// Opens a Realtime channel and streams newly-inserted updates for one flight. The caller
    /// owns the channel's lifetime and must pass it to `supabase.removeChannel(_:)` when the
    /// screen watching it disappears.
    static func subscribeToFlightUpdates(flightID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<FlightUpdate>) {
        let channel = supabase.channel("flight_updates_\(flightID.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            table: "flight_updates",
            filter: .eq("flight_id", value: flightID.uuidString)
        )

        let (stream, continuation) = AsyncStream<FlightUpdate>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            for await insertion in insertions {
                guard let row = try? insertion.decodeRecord(as: FlightUpdateRow.self, decoder: AnyJSON.decoder) else { continue }
                continuation.yield(FlightUpdate(id: row.id, kind: row.kind, note: row.note, createdAt: row.createdAt))
            }
            continuation.finish()
        }

        return (channel, stream)
    }

    static func unsubscribe(_ channel: RealtimeChannelV2) async {
        await supabase.removeChannel(channel)
    }

    // MARK: - Memories

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private struct MemoryRow: Decodable {
        var id: UUID
        var placeId: UUID
        var title: String
        var emoji: String
        var note: String
        var photoPath: String?
        var occurredOn: String

        enum CodingKeys: String, CodingKey {
            case id, title, emoji, note
            case placeId = "place_id"
            case photoPath = "photo_path"
            case occurredOn = "occurred_on"
        }

        var occurredOnDate: Date? {
            BackendService.dateOnlyFormatter.date(from: occurredOn)
        }
    }

    private struct MemoryInsert: Encodable {
        var id: UUID
        var coupleId: UUID
        var placeId: UUID
        var title: String
        var emoji: String
        var note: String
        var photoPath: String?
        var occurredOn: String

        enum CodingKeys: String, CodingKey {
            case id, title, emoji, note
            case coupleId = "couple_id"
            case placeId = "place_id"
            case photoPath = "photo_path"
            case occurredOn = "occurred_on"
        }
    }

    /// `memory-photos` is a private bucket (unlike `avatars`) — these are personal photos —
    /// so display goes through a time-limited signed URL rather than a stable public one.
    static func memoryPhotoSignedURL(path: String) async throws -> URL {
        try await supabase.storage.from("memory-photos").createSignedURL(path: path, expiresIn: 3600)
    }

    static func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String {
        let path = "\(coupleID)/\(memoryID).jpg"
        try await supabase.storage.from("memory-photos").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        return path
    }

    static func insertMemory(coupleID: UUID, memory: Memory, photoPath: String?) async throws {
        let placeID = try await findOrCreatePlaceID(memory.place)
        try await supabase
            .from("memories")
            .insert(
                MemoryInsert(
                    id: memory.id,
                    coupleId: coupleID,
                    placeId: placeID,
                    title: memory.title,
                    emoji: memory.emoji,
                    note: memory.note,
                    photoPath: photoPath,
                    occurredOn: dateOnlyFormatter.string(from: memory.date)
                )
            )
            .execute()
    }
}

private extension TripCategory {
    var dbValue: String {
        switch self {
        case .seeingEachOther: "seeing_each_other"
        case .together: "together"
        case .personal: "personal"
        }
    }

    init?(dbValue: String) {
        switch dbValue {
        case "seeing_each_other": self = .seeingEachOther
        case "together": self = .together
        case "personal": self = .personal
        default: return nil
        }
    }
}
