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

    /// Forwarded as the `Authorization` header when calling Edge Functions that need to know
    /// who's calling (e.g. `resolve-flight`/`add-flight`/`refresh-flight` — see
    /// `AeroFlightService`) so the function can build a request-scoped, RLS-respecting client.
    static var currentAccessToken: String? {
        supabase.auth.currentSession?.accessToken
    }

    /// Restores a persisted session (if any) on launch. supabase-swift keeps the refresh
    /// token in the Keychain, so this succeeds silently across app relaunches.
    static func restoreSession() async -> Session? {
        try? await supabase.auth.session
    }

    static func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// Everything about a solo (pre-pairing) user worth restoring on relaunch: their own
    /// profile, plus the anniversary date, their own custom photo of their partner (always
    /// personal), and their own nickname for their partner (also always personal — see
    /// `updatePartnerNickname`). `partnerHomeCity` is different: it's only ever a guess until
    /// a real couple exists, since once paired the city is shared/real, not personal.
    struct OwnProfileState {
        var person: Person
        var partnerName: String?
        var partnerHomeCity: Place?
        var partnerAvatarURL: URL?
        var anniversaryDate: Date?
        var subscriptionActive: Bool
    }

    /// The signed-in user's own profile — used when they're authenticated but not (yet)
    /// paired with a partner, so `AppModel` can show their real name/photo/city instead of
    /// routing them back through onboarding just because no `couples` row exists yet.
    static func fetchOwnProfile() async throws -> OwnProfileState? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [ProfileRow] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let profile = rows.first else { return nil }

        var placeIDs: [UUID] = []
        if let id = profile.homePlaceId { placeIDs.append(id) }
        if let id = profile.partnerHomePlaceId { placeIDs.append(id) }
        let places = try await fetchPlaces(ids: placeIDs)

        let person = Person(
            id: profile.id,
            name: profile.firstName.isEmpty ? "You" : profile.firstName,
            homeCity: profile.homePlaceId.flatMap { places[$0] },
            accentColor: Person.palette[1],
            avatarURL: profile.avatarPath.flatMap { avatarPublicURL(path: $0) }
        )

        return OwnProfileState(
            person: person,
            partnerName: profile.partnerName,
            partnerHomeCity: profile.partnerHomePlaceId.flatMap { places[$0] },
            partnerAvatarURL: profile.partnerAvatarPath.flatMap { avatarPublicURL(path: $0) },
            anniversaryDate: profile.anniversaryDate.flatMap { Self.dateOnlyFormatter.date(from: $0) },
            subscriptionActive: profile.subscriptionActive
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
        var partnerName: String?
        var partnerHomePlaceId: UUID?
        var anniversaryDate: String?
        var subscriptionActive: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case homePlaceId = "home_place_id"
            case avatarPath = "avatar_path"
            case partnerAvatarPath = "partner_avatar_path"
            case partnerName = "partner_name"
            case partnerHomePlaceId = "partner_home_place_id"
            case anniversaryDate = "anniversary_date"
            case subscriptionActive = "subscription_active"
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

    private struct PartnerNameUpdate: Encodable {
        var partnerName: String
        enum CodingKeys: String, CodingKey { case partnerName = "partner_name" }
    }

    /// Stored on the signed-in user's own profile row — this is always *their own, personal*
    /// name for their partner (a nickname, a pet name, however they think of them), never the
    /// partner's real data. Unlike `updatePartnerHomeCityGuess`, this stays in effect even
    /// after real pairing — two partners can each have a different name for the other, and
    /// neither overwrites the other's. Falls back to the partner's real `first_name` only when
    /// this is empty (see `fetchCoupleState`'s `person(for:nameOverride:...)`).
    static func updatePartnerNickname(_ name: String) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(PartnerNameUpdate(partnerName: name))
            .eq("id", value: userID)
            .execute()
    }

    private struct PartnerHomeCityUpdate: Encodable {
        var partnerHomePlaceId: UUID
        enum CodingKeys: String, CodingKey { case partnerHomePlaceId = "partner_home_place_id" }
    }

    /// Unlike `updatePartnerNickname`, this one *is* just a pre-pairing guess — the signed-in
    /// user's best guess at their partner's city, superseded by the partner's own real
    /// `home_place_id` once actually paired (home city is shared/real, not personal).
    static func updatePartnerHomeCityGuess(_ place: Place) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let placeID = try await findOrCreatePlaceID(place)
        try await supabase
            .from("profiles")
            .update(PartnerHomeCityUpdate(partnerHomePlaceId: placeID))
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

    private struct SubscriptionStatusUpdate: Encodable {
        var subscriptionActive: Bool
        var subscriptionCheckedAt: Date
        enum CodingKeys: String, CodingKey {
            case subscriptionActive = "subscription_active"
            case subscriptionCheckedAt = "subscription_checked_at"
        }
    }

    /// Writes only the caller's own profile row with their own device's last-known local
    /// StoreKit entitlement — never the partner's, so there's no clobbering risk between two
    /// independently-checking devices (see `fetchSubscriptionActive`, which ORs the two).
    static func updateSubscriptionStatus(active: Bool) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(SubscriptionStatusUpdate(subscriptionActive: active, subscriptionCheckedAt: .now))
            .eq("id", value: userID)
            .execute()
    }

    private struct SubscriptionActiveRow: Decodable {
        var subscriptionActive: Bool
        enum CodingKeys: String, CodingKey { case subscriptionActive = "subscription_active" }
    }

    /// Cheap, dedicated status check — deliberately not `fetchCoupleState()` (which also pulls
    /// trips/flights/memories/places), since this needs to be re-checked periodically
    /// (app foreground), not just once at cold launch. "Your partner doesn't pay anything" —
    /// true if *either* partner's profile reports an active subscription; solo (unpaired)
    /// users only have their own row to check.
    static func fetchSubscriptionActive() async throws -> Bool {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        let profileIDs: [UUID]
        if let couple = coupleRows.first {
            profileIDs = [couple.partnerAId, couple.partnerBId]
        } else {
            profileIDs = [userID]
        }

        let rows: [SubscriptionActiveRow] = try await supabase
            .from("profiles")
            .select("subscription_active")
            .in("id", values: profileIDs)
            .execute()
            .value

        return rows.contains { $0.subscriptionActive }
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

    /// Every avatar lives at a fixed, deterministic path (`{userID}/avatar.jpg`) so re-uploads
    /// overwrite rather than accumulate — but that means `avatarPublicURL` returns the exact
    /// same URL string before and after a re-upload, and `AsyncImage`/`URLCache` then keep
    /// showing the stale cached image instead of fetching the new one. Appending a
    /// cache-busting query item makes each fresh upload's URL genuinely new. Only used right
    /// after an upload succeeds — regular reads (`fetchCoupleState`, `fetchOwnProfile`) still
    /// use the plain cacheable URL, since nothing changed for those.
    private static func freshAvatarURL(path: String) -> URL? {
        guard let base = avatarPublicURL(path: path),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "v", value: "\(Int(Date().timeIntervalSince1970 * 1000))")]
        return components.url
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

        guard let url = freshAvatarURL(path: path) else { throw BackendError.avatarURLFailed }
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

        guard let url = freshAvatarURL(path: path) else { throw BackendError.avatarURLFailed }
        return url
    }

    // MARK: - Drawing pads

    /// Each person's home-screen doodle lives at one fixed path, so a re-save overwrites
    /// rather than accumulates — no separate DB row needed, the path is fully deterministic.
    private static func drawingPadPath(coupleID: UUID, personID: UUID) -> String {
        "\(coupleID)/\(personID)/pad.png"
    }

    static func drawingPadPublicURL(coupleID: UUID, personID: UUID) -> URL? {
        try? supabase.storage.from("drawing-pads").getPublicURL(path: drawingPadPath(coupleID: coupleID, personID: personID))
    }

    /// Uploads the signed-in user's drawing pad and returns a cache-busted URL for immediate
    /// local display — same staleness fix as `freshAvatarURL`, since the path never changes.
    @discardableResult
    static func uploadDrawingPad(coupleID: UUID, personID: UUID, imageData: Data) async throws -> URL {
        let path = drawingPadPath(coupleID: coupleID, personID: personID)
        try await supabase.storage.from("drawing-pads").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/png", upsert: true)
        )
        guard let base = drawingPadPublicURL(coupleID: coupleID, personID: personID),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BackendError.avatarURLFailed
        }
        components.queryItems = [URLQueryItem(name: "v", value: "\(Int(Date().timeIntervalSince1970 * 1000))")]
        return components.url ?? base
    }

    // MARK: - Couple pairing

    private struct CoupleRow: Decodable {
        var id: UUID
        var partnerAId: UUID
        var partnerBId: UUID
        var status: String
        var dissolvedAt: Date?
        var startedDatingOn: Date?

        enum CodingKeys: String, CodingKey {
            case id, status
            case partnerAId = "partner_a_id"
            case partnerBId = "partner_b_id"
            case dissolvedAt = "dissolved_at"
            case startedDatingOn = "started_dating_on"
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

    // MARK: - Remove partner / archived data

    /// Dissolves the couple — doesn't delete anything. Trips/memories/flights/game sessions
    /// stay in place and remain readable (existing RLS has no active-status gate on their
    /// SELECT policies), just no longer the caller's *active* couple, so the app naturally
    /// stops surfacing them in normal views. Either partner can call this unilaterally.
    @discardableResult
    static func leaveCouple(coupleID: UUID) async throws -> UUID {
        struct Params: Encodable {
            var pCoupleId: UUID
            enum CodingKeys: String, CodingKey { case pCoupleId = "p_couple_id" }
        }
        let row: CoupleRow = try await supabase
            .rpc("leave_couple", params: Params(pCoupleId: coupleID))
            .single()
            .execute()
            .value
        return row.id
    }

    /// Permanently deletes a *dissolved* couple's data — trips, memories, flights (and their
    /// events/prefs/documents), game sessions, and the associated storage objects (memory
    /// photos, flight documents, drawing pads). The RPC itself refuses to run on an active
    /// couple, so this can never be triggered on live, in-use data.
    static func deleteDissolvedCoupleData(coupleID: UUID) async throws {
        struct Params: Encodable {
            var pCoupleId: UUID
            enum CodingKeys: String, CodingKey { case pCoupleId = "p_couple_id" }
        }
        try await supabase
            .rpc("delete_dissolved_couple_data", params: Params(pCoupleId: coupleID))
            .execute()
    }

    /// Every couple the signed-in user has since dissolved, newest first — the source list for
    /// Settings' "Archived data" screen. `partnerName` is that couple's *other* member's current
    /// first name (profiles stay readable regardless of couple status, see
    /// `profiles_select_self_or_partner`).
    static func fetchArchivedCouples() async throws -> [ArchivedCouple] {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "dissolved")
            .order("dissolved_at", ascending: false)
            .execute()
            .value
        guard !coupleRows.isEmpty else { return [] }

        let partnerIDs = coupleRows.map { $0.partnerAId == userID ? $0.partnerBId : $0.partnerAId }
        let profileRows: [ProfileRow] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: partnerIDs)
            .execute()
            .value
        let namesByID = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id, $0.firstName.isEmpty ? "Partner" : $0.firstName) })

        return coupleRows.map { row in
            let partnerID = row.partnerAId == userID ? row.partnerBId : row.partnerAId
            return ArchivedCouple(
                id: row.id,
                partnerName: namesByID[partnerID] ?? "Partner",
                startedDatingOn: row.startedDatingOn,
                dissolvedAt: row.dissolvedAt
            )
        }
    }

    /// Lightweight counts for the archive detail screen — fetches just `id` columns rather than
    /// full rows, since only the counts are shown.
    static func fetchArchivedCoupleSummary(coupleID: UUID) async throws -> ArchivedCoupleSummary {
        struct IDRow: Decodable { var id: UUID }

        async let tripRows: [IDRow] = supabase.from("trips").select("id").eq("couple_id", value: coupleID).execute().value
        async let memoryRows: [IDRow] = supabase.from("memories").select("id").eq("couple_id", value: coupleID).execute().value
        async let flightRows: [IDRow] = supabase.from("flights").select("id").eq("couple_id", value: coupleID).execute().value
        async let gameRows: [IDRow] = supabase.from("game_sessions").select("id").eq("couple_id", value: coupleID).execute().value

        let (trips, memories, flights, games) = try await (tripRows, memoryRows, flightRows, gameRows)
        return ArchivedCoupleSummary(tripCount: trips.count, memoryCount: memories.count, flightCount: flights.count, gameSessionCount: games.count)
    }

    // MARK: - Couple state (couple + both profiles + trips + flights + memories)

    struct CoupleState {
        var couple: Couple
        var trips: [Trip]
        var memories: [Memory]
        /// Every flight for the couple — the authoritative list. Trip-linked flights are also
        /// mirrored onto `trip.flight` for backward compatibility with trip-scoped UI.
        var flights: [Flight]
        /// "Your partner doesn't pay anything" — access is granted if *either* partner's
        /// device last reported an active local StoreKit entitlement.
        var subscriptionActive: Bool
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

        // Flights are couple-scoped directly (not joined through trips) — a flight can exist
        // with no trip link at all.
        let flightRows: [FlightRow] = try await supabase
            .from("flights")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        let memoryRows: [MemoryRow] = try await supabase
            .from("memories")
            .select()
            .eq("couple_id", value: coupleRow.id)
            .execute()
            .value

        let memoryPhotoRows: [MemoryPhotoRow]
        if memoryRows.isEmpty {
            memoryPhotoRows = []
        } else {
            memoryPhotoRows = try await supabase
                .from("memory_photos")
                .select()
                .in("memory_id", values: memoryRows.map(\.id))
                .order("position")
                .execute()
                .value
        }

        var placeIDs = Set([partnerAProfile.homePlaceId, partnerBProfile.homePlaceId].compactMap { $0 })
        for row in tripRows { placeIDs.insert(row.originId); placeIDs.insert(row.destinationId) }
        for row in memoryRows { if let placeId = row.placeId { placeIDs.insert(placeId) } }
        let places = try await fetchPlaces(ids: Array(placeIDs))

        func person(for profile: ProfileRow, nameOverride: String?, avatarOverridePath: String?, paletteIndex: Int) -> Person {
            let avatarPath = avatarOverridePath ?? profile.avatarPath
            let name = (nameOverride?.isEmpty == false) ? nameOverride! : (profile.firstName.isEmpty ? "Partner" : profile.firstName)
            return Person(
                id: profile.id,
                name: name,
                homeCity: profile.homePlaceId.flatMap { places[$0] },
                accentColor: Person.palette[paletteIndex],
                avatarURL: avatarPath.flatMap { avatarPublicURL(path: $0) }
            )
        }

        let couple = Couple(
            id: coupleRow.id,
            // Nobody overrides how I see myself — my own name and avatar are always my own.
            partnerA: person(for: meProfile, nameOverride: nil, avatarOverridePath: nil, paletteIndex: 1),
            // My partner, as *I* personally see them: a nickname if I've set one (independent
            // of whatever nickname, if any, they've set for me — each side's `partner_name`
            // lives on their own profile row), otherwise their real first name. Same idea for
            // the avatar — my own custom photo of them if I've set one, otherwise their own.
            // Home city is never overridden — that one's always shared/real once paired.
            partnerB: person(for: partnerProfile, nameOverride: meProfile.partnerName, avatarOverridePath: meProfile.partnerAvatarPath, paletteIndex: 0),
            startedDatingOn: .now
        )

        let flights = flightRows.map { Self.makeFlight(from: $0) }
        // A trip can have at most one *meaningfully* linked flight for the existing trip-scoped
        // UI (TripsListView, GlobeHomeView's reunion card) — first-match is fine since that's
        // the only shape the current add-flight flows ever produce.
        let flightsByTrip = Dictionary(flights.compactMap { flight in flight.tripID.map { ($0, flight) } }, uniquingKeysWith: { first, _ in first })

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
            trip.flight = flightsByTrip[row.id]
            return trip
        }

        let photoRowsByMemory = Dictionary(grouping: memoryPhotoRows, by: \.memoryId)

        var memories: [Memory] = []
        for row in memoryRows {
            let place = row.placeId.flatMap { places[$0] }
            let photoRows = (photoRowsByMemory[row.id] ?? []).sorted { $0.position < $1.position }
            var photos: [MemoryPhoto] = []
            for photoRow in photoRows {
                if let url = await memoryPhotoSignedURLWithRetry(path: photoRow.photoPath) {
                    photos.append(MemoryPhoto(id: photoRow.id, path: photoRow.photoPath, url: url))
                }
            }
            memories.append(
                Memory(
                    id: row.id,
                    title: row.title,
                    place: place,
                    date: row.occurredAt,
                    note: row.note,
                    photos: photos,
                    tripID: row.tripId
                )
            )
        }

        return CoupleState(
            couple: couple,
            trips: trips,
            memories: memories,
            flights: flights,
            subscriptionActive: meProfile.subscriptionActive || partnerProfile.subscriptionActive
        )
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

    /// Flights are couple-scoped (not trip-scoped) — `tripId` is an optional link, not a
    /// join key. `status`/`progress`/`timeline` on the app-side `Flight` model are computed
    /// from these raw timestamps rather than duplicated here.
    private struct FlightRow: Decodable {
        var id: UUID
        var tripId: UUID?
        var coupleId: UUID
        var createdBy: UUID?
        var travelerId: UUID?
        var faFlightId: String?
        var flightNumberIata: String
        var flightNumberIcao: String?
        var airlineName: String?
        var airlineCode: String?
        var airlineLogoUrl: String?
        var originIata: String?
        var originIcao: String?
        var originName: String?
        var originCity: String?
        var originTimezone: String?
        var originLatitude: Double?
        var originLongitude: Double?
        var destinationIata: String?
        var destinationIcao: String?
        var destinationName: String?
        var destinationCity: String?
        var destinationTimezone: String?
        var destinationLatitude: Double?
        var destinationLongitude: Double?
        var aircraftType: String?
        var registration: String?
        var route: String?
        var scheduledOut: Date?
        var scheduledOff: Date?
        var scheduledOn: Date?
        var scheduledIn: Date?
        var estimatedOut: Date?
        var estimatedOff: Date?
        var estimatedOn: Date?
        var estimatedIn: Date?
        var actualOut: Date?
        var actualOff: Date?
        var actualOn: Date?
        var actualIn: Date?
        var departureDelaySeconds: Int?
        var arrivalDelaySeconds: Int?
        var terminalOrigin: String?
        var gateOrigin: String?
        var terminalDestination: String?
        var gateDestination: String?
        var baggageClaim: String?
        var cancelled: Bool
        var diverted: Bool
        var status: String
        var positionLatitude: Double?
        var positionLongitude: Double?
        var positionAltitude: Double?
        var positionGroundspeed: Double?
        var positionHeading: Double?
        var positionUpdatedAt: Date?
        var weatherOrigin: FlightWeather?
        var weatherDestination: FlightWeather?
        var lastRefreshedAt: Date?
        var trackingEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case id, cancelled, diverted, status, route, registration
            case tripId = "trip_id"
            case coupleId = "couple_id"
            case createdBy = "created_by"
            case travelerId = "traveler_id"
            case faFlightId = "fa_flight_id"
            case flightNumberIata = "flight_number_iata"
            case flightNumberIcao = "flight_number_icao"
            case airlineName = "airline_name"
            case airlineCode = "airline_code"
            case airlineLogoUrl = "airline_logo_url"
            case originIata = "origin_iata"
            case originIcao = "origin_icao"
            case originName = "origin_name"
            case originCity = "origin_city"
            case originTimezone = "origin_timezone"
            case originLatitude = "origin_latitude"
            case originLongitude = "origin_longitude"
            case destinationIata = "destination_iata"
            case destinationIcao = "destination_icao"
            case destinationName = "destination_name"
            case destinationCity = "destination_city"
            case destinationTimezone = "destination_timezone"
            case destinationLatitude = "destination_latitude"
            case destinationLongitude = "destination_longitude"
            case aircraftType = "aircraft_type"
            case scheduledOut = "scheduled_out"
            case scheduledOff = "scheduled_off"
            case scheduledOn = "scheduled_on"
            case scheduledIn = "scheduled_in"
            case estimatedOut = "estimated_out"
            case estimatedOff = "estimated_off"
            case estimatedOn = "estimated_on"
            case estimatedIn = "estimated_in"
            case actualOut = "actual_out"
            case actualOff = "actual_off"
            case actualOn = "actual_on"
            case actualIn = "actual_in"
            case departureDelaySeconds = "departure_delay_seconds"
            case arrivalDelaySeconds = "arrival_delay_seconds"
            case terminalOrigin = "terminal_origin"
            case gateOrigin = "gate_origin"
            case terminalDestination = "terminal_destination"
            case gateDestination = "gate_destination"
            case baggageClaim = "baggage_claim"
            case positionLatitude = "position_latitude"
            case positionLongitude = "position_longitude"
            case positionAltitude = "position_altitude"
            case positionGroundspeed = "position_groundspeed"
            case positionHeading = "position_heading"
            case positionUpdatedAt = "position_updated_at"
            case weatherOrigin = "weather_origin"
            case weatherDestination = "weather_destination"
            case lastRefreshedAt = "last_refreshed_at"
            case trackingEnabled = "tracking_enabled"
        }
    }

    private static func makeFlight(from row: FlightRow) -> Flight {
        Flight(
            id: row.id,
            tripID: row.tripId,
            coupleID: row.coupleId,
            createdBy: row.createdBy,
            travelerID: row.travelerId,
            faFlightID: row.faFlightId,
            flightNumberIATA: row.flightNumberIata,
            flightNumberICAO: row.flightNumberIcao,
            airlineName: row.airlineName,
            airlineCode: row.airlineCode,
            airlineLogoURL: row.airlineLogoUrl.flatMap(URL.init(string:)),
            origin: FlightAirport(iata: row.originIata, icao: row.originIcao, name: row.originName, city: row.originCity, timezone: row.originTimezone, latitude: row.originLatitude, longitude: row.originLongitude),
            destination: FlightAirport(iata: row.destinationIata, icao: row.destinationIcao, name: row.destinationName, city: row.destinationCity, timezone: row.destinationTimezone, latitude: row.destinationLatitude, longitude: row.destinationLongitude),
            aircraftType: row.aircraftType,
            registration: row.registration,
            route: row.route,
            scheduledOut: row.scheduledOut,
            scheduledOff: row.scheduledOff,
            scheduledOn: row.scheduledOn,
            scheduledIn: row.scheduledIn,
            estimatedOut: row.estimatedOut,
            estimatedOff: row.estimatedOff,
            estimatedOn: row.estimatedOn,
            estimatedIn: row.estimatedIn,
            actualOut: row.actualOut,
            actualOff: row.actualOff,
            actualOn: row.actualOn,
            actualIn: row.actualIn,
            departureDelaySeconds: row.departureDelaySeconds,
            arrivalDelaySeconds: row.arrivalDelaySeconds,
            terminalOrigin: row.terminalOrigin,
            gateOrigin: row.gateOrigin,
            terminalDestination: row.terminalDestination,
            gateDestination: row.gateDestination,
            baggageClaim: row.baggageClaim,
            cancelled: row.cancelled,
            diverted: row.diverted,
            status: FlightStatus(rawValue: row.status) ?? .scheduled,
            positionLatitude: row.positionLatitude,
            positionLongitude: row.positionLongitude,
            positionAltitude: row.positionAltitude,
            positionGroundspeed: row.positionGroundspeed,
            positionHeading: row.positionHeading,
            positionUpdatedAt: row.positionUpdatedAt,
            weatherOrigin: row.weatherOrigin,
            weatherDestination: row.weatherDestination,
            lastRefreshedAt: row.lastRefreshedAt,
            trackingEnabled: row.trackingEnabled
        )
    }

    static func fetchFlights(coupleID: UUID) async throws -> [Flight] {
        let rows: [FlightRow] = try await supabase
            .from("flights")
            .select()
            .eq("couple_id", value: coupleID)
            .execute()
            .value
        return rows.map(Self.makeFlight)
    }

    static func fetchFlight(id: UUID) async throws -> Flight? {
        let rows: [FlightRow] = try await supabase
            .from("flights")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first.map(Self.makeFlight)
    }

    /// Stops tracking a flight entirely — status events, notification preferences, and
    /// documents all cascade-delete with it (see the flights_delete_members migration).
    static func deleteFlight(id: UUID) async throws {
        try await supabase
            .from("flights")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Flight status events (provider-sourced) & notification preferences

    private struct FlightStatusEventRow: Decodable {
        var id: UUID
        var flightId: UUID
        var type: FlightStatusEventType
        var previousValue: String?
        var newValue: String?
        var occurredAt: Date
        var source: String

        enum CodingKeys: String, CodingKey {
            case id, type, source
            case flightId = "flight_id"
            case previousValue = "previous_value"
            case newValue = "new_value"
            case occurredAt = "occurred_at"
        }

        func toModel() -> FlightStatusEvent {
            FlightStatusEvent(id: id, flightID: flightId, type: type, previousValue: previousValue, newValue: newValue, occurredAt: occurredAt, source: source)
        }
    }

    static func fetchFlightStatusEvents(flightID: UUID) async throws -> [FlightStatusEvent] {
        let rows: [FlightStatusEventRow] = try await supabase
            .from("flight_status_events")
            .select()
            .eq("flight_id", value: flightID)
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    /// Mirrors `subscribeToFlightUpdates` — a Realtime channel of newly-inserted provider
    /// events, written server-side by the AeroAPI sync pipeline.
    static func subscribeToFlightStatusEvents(flightID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<FlightStatusEvent>) {
        let channel = supabase.channel("flight_status_events_\(flightID.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            table: "flight_status_events",
            filter: .eq("flight_id", value: flightID.uuidString)
        )

        let (stream, continuation) = AsyncStream<FlightStatusEvent>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            for await insertion in insertions {
                guard let row = try? insertion.decodeRecord(as: FlightStatusEventRow.self, decoder: AnyJSON.decoder) else { continue }
                continuation.yield(row.toModel())
            }
            continuation.finish()
        }
        return (channel, stream)
    }

    private struct NotificationPreferencesRow: Codable {
        var flightId: UUID
        var profileId: UUID
        var gateTerminalChanges: Bool
        var delayOrCancellation: Bool
        var departure: Bool
        var landing: Bool
        var arrivalAtGate: Bool
        var baggageClaimUpdate: Bool

        enum CodingKeys: String, CodingKey {
            case flightId = "flight_id"
            case profileId = "profile_id"
            case gateTerminalChanges = "gate_terminal_changes"
            case delayOrCancellation = "delay_or_cancellation"
            case departure, landing
            case arrivalAtGate = "arrival_at_gate"
            case baggageClaimUpdate = "baggage_claim_update"
        }

        func toModel() -> FlightNotificationPreferences {
            FlightNotificationPreferences(
                flightID: flightId, profileID: profileId,
                gateTerminalChanges: gateTerminalChanges, delayOrCancellation: delayOrCancellation,
                departure: departure, landing: landing,
                arrivalAtGate: arrivalAtGate, baggageClaimUpdate: baggageClaimUpdate
            )
        }
    }

    static func fetchNotificationPreferences(flightID: UUID) async throws -> FlightNotificationPreferences? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [NotificationPreferencesRow] = try await supabase
            .from("flight_notification_preferences")
            .select()
            .eq("flight_id", value: flightID)
            .eq("profile_id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first?.toModel()
    }

    static func upsertNotificationPreferences(_ prefs: FlightNotificationPreferences) async throws {
        try await supabase
            .from("flight_notification_preferences")
            .upsert(NotificationPreferencesRow(
                flightId: prefs.flightID, profileId: prefs.profileID,
                gateTerminalChanges: prefs.gateTerminalChanges, delayOrCancellation: prefs.delayOrCancellation,
                departure: prefs.departure, landing: prefs.landing,
                arrivalAtGate: prefs.arrivalAtGate, baggageClaimUpdate: prefs.baggageClaimUpdate
            ), onConflict: "flight_id,profile_id")
            .execute()
    }

    // MARK: - Flight documents (boarding passes / travel docs)

    private struct FlightDocumentRow: Decodable {
        var id: UUID
        var flightId: UUID?
        var tripId: UUID?
        var uploadedBy: UUID
        var docType: FlightDocumentType
        var filePath: String
        var originalFilename: String?
        var contentType: String?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case flightId = "flight_id"
            case tripId = "trip_id"
            case uploadedBy = "uploaded_by"
            case docType = "doc_type"
            case filePath = "file_path"
            case originalFilename = "original_filename"
            case contentType = "content_type"
            case createdAt = "created_at"
        }
    }

    private struct FlightDocumentInsert: Encodable {
        var flightId: UUID?
        var tripId: UUID?
        var uploadedBy: UUID
        var docType: String
        var filePath: String
        var originalFilename: String?
        var contentType: String?

        enum CodingKeys: String, CodingKey {
            case flightId = "flight_id"
            case tripId = "trip_id"
            case uploadedBy = "uploaded_by"
            case docType = "doc_type"
            case filePath = "file_path"
            case originalFilename = "original_filename"
            case contentType = "content_type"
        }
    }

    static func flightDocumentSignedURL(path: String) async throws -> URL {
        try await supabase.storage.from("flight-documents").createSignedURL(path: path, expiresIn: 3600)
    }

    static func uploadFlightDocument(coupleID: UUID, parentID: UUID, data: Data, contentType: String, fileExtension: String) async throws -> String {
        let path = "\(coupleID)/\(parentID)/\(UUID().uuidString).\(fileExtension)"
        try await supabase.storage.from("flight-documents").upload(
            path,
            data: data,
            options: FileOptions(contentType: contentType, upsert: true)
        )
        return path
    }

    @discardableResult
    static func insertFlightDocument(coupleID: UUID, flightID: UUID?, tripID: UUID?, docType: FlightDocumentType, data: Data, contentType: String, fileExtension: String, originalFilename: String?) async throws -> FlightDocument {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let parentID = flightID ?? tripID
        guard let parentID else { throw BackendError.notAuthenticated }
        let path = try await uploadFlightDocument(coupleID: coupleID, parentID: parentID, data: data, contentType: contentType, fileExtension: fileExtension)

        let insert = FlightDocumentInsert(
            flightId: flightID, tripId: tripID, uploadedBy: userID,
            docType: docType.rawValue, filePath: path, originalFilename: originalFilename, contentType: contentType
        )
        let rows: [FlightDocumentRow] = try await supabase
            .from("flight_documents")
            .insert(insert)
            .select()
            .execute()
            .value
        guard let row = rows.first else { throw BackendError.avatarURLFailed }
        let url = try? await flightDocumentSignedURL(path: row.filePath)
        return FlightDocument(id: row.id, flightID: row.flightId, tripID: row.tripId, uploadedBy: row.uploadedBy, docType: row.docType, filePath: row.filePath, originalFilename: row.originalFilename, contentType: row.contentType, createdAt: row.createdAt, url: url)
    }

    static func fetchFlightDocuments(flightID: UUID? = nil, tripID: UUID? = nil) async throws -> [FlightDocument] {
        var query = supabase.from("flight_documents").select()
        if let flightID {
            query = query.eq("flight_id", value: flightID)
        } else if let tripID {
            query = query.eq("trip_id", value: tripID)
        } else {
            return []
        }
        let rows: [FlightDocumentRow] = try await query.order("created_at", ascending: false).execute().value

        var documents: [FlightDocument] = []
        for row in rows {
            let url = try? await flightDocumentSignedURL(path: row.filePath)
            documents.append(FlightDocument(id: row.id, flightID: row.flightId, tripID: row.tripId, uploadedBy: row.uploadedBy, docType: row.docType, filePath: row.filePath, originalFilename: row.originalFilename, contentType: row.contentType, createdAt: row.createdAt, url: url))
        }
        return documents
    }

    static func deleteFlightDocument(id: UUID) async throws {
        try await supabase.from("flight_documents").delete().eq("id", value: id).execute()
    }

    // MARK: - Push device tokens

    private struct DeviceTokenUpsert: Encodable {
        var profileId: UUID
        var apnsToken: String
        var environment: String
        var lastSeenAt: Date

        enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
            case apnsToken = "apns_token"
            case environment
            case lastSeenAt = "last_seen_at"
        }
    }

    static func registerDeviceToken(_ token: String, environment: String) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("device_push_tokens")
            .upsert(DeviceTokenUpsert(profileId: userID, apnsToken: token, environment: environment, lastSeenAt: .now), onConflict: "apns_token")
            .execute()
    }

    private struct TripNotesUpdate: Encodable {
        var notes: String?
    }

    static func updateTripNotes(tripID: UUID, notes: String?) async throws {
        try await supabase
            .from("trips")
            .update(TripNotesUpdate(notes: notes))
            .eq("id", value: tripID)
            .execute()
    }

    /// Inserts a trip using the client-generated id already on `trip`, resolving origin/
    /// destination against the `places` table. Never writes a flight — flights are only ever
    /// written by the `add-flight`/`refresh-flight` Edge Functions (service role key) once a
    /// real AeroAPI candidate is resolved via `AeroFlightService.addFlight`, called separately
    /// once the trip this returns exists.
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
    }

    private struct TripUpdate: Encodable {
        var travelerId: UUID
        var originId: UUID
        var destinationId: UUID
        var departureAt: Date
        var arrivalAt: Date
        var category: String
        var distanceKm: Double
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case category, notes
            case travelerId = "traveler_id"
            case originId = "origin_id"
            case destinationId = "destination_id"
            case departureAt = "departure_at"
            case arrivalAt = "arrival_at"
            case distanceKm = "distance_km"
        }
    }

    /// Full edit of a trip's own fields, as opposed to `updateTripNotes` (notes only) —
    /// resolves origin/destination against `places` fresh, same as `insertTrip`, since either
    /// city could have changed.
    static func updateTrip(_ trip: Trip) async throws {
        let originID = try await findOrCreatePlaceID(trip.origin)
        let destinationID = try await findOrCreatePlaceID(trip.destination)
        try await supabase
            .from("trips")
            .update(
                TripUpdate(
                    travelerId: trip.travelerID,
                    originId: originID,
                    destinationId: destinationID,
                    departureAt: trip.departureDate,
                    arrivalAt: trip.arrivalDate,
                    category: trip.category.dbValue,
                    distanceKm: trip.distanceKm,
                    notes: trip.notes
                )
            )
            .eq("id", value: trip.id)
            .execute()
    }

    /// `flights.trip_id`/`memories.trip_id` both have `on delete set null`, so any linked
    /// flight or memory survives untethered rather than disappearing along with the trip.
    static func deleteTrip(id: UUID) async throws {
        try await supabase.from("trips").delete().eq("id", value: id).execute()
    }

    private struct TripIDUpdate: Encodable {
        var tripId: UUID?
        enum CodingKeys: String, CodingKey { case tripId = "trip_id" }
    }

    /// The only way to change `flights.trip_id` after a flight's already been added — every
    /// other write path (`AeroFlightService.addFlight`) only ever sets it once, at creation.
    /// Pass `nil` to unlink.
    static func setFlightTrip(flightID: UUID, tripID: UUID?) async throws {
        try await supabase
            .from("flights")
            .update(TripIDUpdate(tripId: tripID))
            .eq("id", value: flightID)
            .execute()
    }

    /// Pass `nil` to unlink — the only write path for `memories.trip_id`, since a memory has
    /// no other route to a trip (no automatic place/date matching).
    static func setMemoryTrip(memoryID: UUID, tripID: UUID?) async throws {
        try await supabase
            .from("memories")
            .update(TripIDUpdate(tripId: tripID))
            .eq("id", value: memoryID)
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
        var placeId: UUID?
        var title: String
        var note: String
        var occurredAt: Date
        var tripId: UUID?

        enum CodingKeys: String, CodingKey {
            case id, title, note
            case placeId = "place_id"
            case occurredAt = "occurred_at"
            case tripId = "trip_id"
        }
    }

    private struct MemoryInsert: Encodable {
        var id: UUID
        var coupleId: UUID
        var placeId: UUID?
        var title: String
        var note: String
        var occurredAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, note
            case coupleId = "couple_id"
            case placeId = "place_id"
            case occurredAt = "occurred_at"
        }
    }

    private struct MemoryUpdate: Encodable {
        var placeId: UUID?
        var title: String
        var note: String
        var occurredAt: Date

        enum CodingKeys: String, CodingKey {
            case title, note
            case placeId = "place_id"
            case occurredAt = "occurred_at"
        }
    }

    private struct MemoryPhotoRow: Decodable {
        var id: UUID
        var memoryId: UUID
        var photoPath: String
        var position: Int

        enum CodingKeys: String, CodingKey {
            case id, position
            case memoryId = "memory_id"
            case photoPath = "photo_path"
        }
    }

    private struct MemoryPhotoInsert: Encodable {
        var memoryId: UUID
        var photoPath: String
        var position: Int

        enum CodingKeys: String, CodingKey {
            case position
            case memoryId = "memory_id"
            case photoPath = "photo_path"
        }
    }

    /// `memory-photos` is a private bucket (unlike `avatars`) — these are personal photos —
    /// so display goes through a time-limited signed URL rather than a stable public one.
    static func memoryPhotoSignedURL(path: String) async throws -> URL {
        try await supabase.storage.from("memory-photos").createSignedURL(path: path, expiresIn: 3600)
    }

    /// A single transient failure here (network blip, momentary auth hiccup) used to mean a
    /// callers' `try?` silently dropped the photo forever — the underlying file and DB row
    /// were both fine, but the photo just never showed up, looking exactly like "the image
    /// wasn't saved" even though it was. Retries a few times before actually giving up.
    static func memoryPhotoSignedURLWithRetry(path: String, attempts: Int = 3) async -> URL? {
        for attempt in 1...attempts {
            if let url = try? await memoryPhotoSignedURL(path: path) {
                return url
            }
            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        return nil
    }

    /// Path includes a fresh photo id per upload (unlike the old single-photo `{coupleID}/{memoryID}.jpg`
    /// scheme) so a memory can hold more than one photo — the couple id stays the leading path
    /// segment since that's what the storage RLS policies key off.
    static func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String {
        let path = "\(coupleID)/\(memoryID)/\(UUID().uuidString).jpg"
        try await supabase.storage.from("memory-photos").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        return path
    }

    @discardableResult
    static func insertMemory(coupleID: UUID, memory: Memory, photoPaths: [String]) async throws -> [MemoryPhoto] {
        var placeID: UUID?
        if let place = memory.place {
            placeID = try await findOrCreatePlaceID(place)
        }
        try await supabase
            .from("memories")
            .insert(
                MemoryInsert(
                    id: memory.id,
                    coupleId: coupleID,
                    placeId: placeID,
                    title: memory.title,
                    note: memory.note,
                    occurredAt: memory.date
                )
            )
            .execute()

        return try await addMemoryPhotos(memoryID: memory.id, photoPaths: photoPaths, startingPosition: 0)
    }

    static func updateMemory(_ memory: Memory) async throws {
        var placeID: UUID?
        if let place = memory.place {
            placeID = try await findOrCreatePlaceID(place)
        }
        try await supabase
            .from("memories")
            .update(
                MemoryUpdate(
                    placeId: placeID,
                    title: memory.title,
                    note: memory.note,
                    occurredAt: memory.date
                )
            )
            .eq("id", value: memory.id)
            .execute()
    }

    /// Appends photos to an existing memory (used both for the initial save and later edits),
    /// returning them with resolved signed URLs ready for local state.
    @discardableResult
    static func addMemoryPhotos(memoryID: UUID, photoPaths: [String], startingPosition: Int) async throws -> [MemoryPhoto] {
        guard !photoPaths.isEmpty else { return [] }
        let inserts = photoPaths.enumerated().map { index, path in
            MemoryPhotoInsert(memoryId: memoryID, photoPath: path, position: startingPosition + index)
        }
        let rows: [MemoryPhotoRow] = try await supabase
            .from("memory_photos")
            .insert(inserts)
            .select()
            .execute()
            .value

        var photos: [MemoryPhoto] = []
        for row in rows.sorted(by: { $0.position < $1.position }) {
            if let url = await memoryPhotoSignedURLWithRetry(path: row.photoPath) {
                photos.append(MemoryPhoto(id: row.id, path: row.photoPath, url: url))
            }
        }
        return photos
    }

    static func deleteMemoryPhoto(id: UUID, path: String) async throws {
        try await supabase.from("memory_photos").delete().eq("id", value: id).execute()
        try? await supabase.storage.from("memory-photos").remove(paths: [path])
    }

    /// `memory_photos` rows cascade-delete with the memory automatically; the underlying
    /// storage objects don't (storage isn't linked by a DB foreign key), so they're removed
    /// explicitly here using the paths the caller already has in local state.
    static func deleteMemory(id: UUID, photoPaths: [String]) async throws {
        try await supabase.from("memories").delete().eq("id", value: id).execute()
        if !photoPaths.isEmpty {
            try? await supabase.storage.from("memory-photos").remove(paths: photoPaths)
        }
    }

    // MARK: - Games

    private struct GameSessionRow: Decodable {
        var id: UUID
        var coupleId: UUID
        var gameType: GameType
        var initiatorId: UUID
        var status: GameSessionStatus
        var totalRounds: Int
        var startedAt: Date?
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, status
            case coupleId = "couple_id"
            case gameType = "game_type"
            case initiatorId = "initiator_id"
            case totalRounds = "total_rounds"
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        func toModel() -> GameSession {
            GameSession(
                id: id, coupleID: coupleId, gameType: gameType, initiatorID: initiatorId, status: status,
                totalRounds: totalRounds, startedAt: startedAt, completedAt: completedAt,
                createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    private struct GameSessionRoundRow: Decodable {
        var id: UUID
        var sessionId: UUID
        var roundNumber: Int
        var contentId: UUID
        var discussionStatus: DiscussionRoundStatus?

        enum CodingKeys: String, CodingKey {
            case id
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case contentId = "content_id"
            case discussionStatus = "discussion_status"
        }

        func toModel() -> GameSessionRound {
            GameSessionRound(id: id, sessionID: sessionId, roundNumber: roundNumber, contentID: contentId, discussionStatus: discussionStatus)
        }
    }

    private struct GameResponseRow: Decodable {
        var id: UUID
        var sessionId: UUID
        var roundNumber: Int
        var responderId: UUID
        var answer: GameAnswerPayload
        var isCorrect: Bool?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, answer
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case responderId = "responder_id"
            case isCorrect = "is_correct"
            case createdAt = "created_at"
        }

        func toModel() -> GameResponse {
            GameResponse(id: id, sessionID: sessionId, roundNumber: roundNumber, responderID: responderId, answerValue: answer.value, isCorrect: isCorrect, createdAt: createdAt)
        }
    }

    private struct GameResponseInsert: Encodable {
        var sessionId: UUID
        var roundNumber: Int
        var responderId: UUID
        var answer: GameAnswerPayload
        var isCorrect: Bool?

        enum CodingKeys: String, CodingKey {
            case answer
            case sessionId = "session_id"
            case roundNumber = "round_number"
            case responderId = "responder_id"
            case isCorrect = "is_correct"
        }
    }

    private struct TriviaQuestionRow: Decodable {
        var id: UUID
        var category: String
        var question: String
        var options: [String]
        var correctAnswer: String
        var explanation: String?
        var difficulty: String?
        var active: Bool

        enum CodingKeys: String, CodingKey {
            case id, category, question, options, explanation, difficulty, active
            case correctAnswer = "correct_answer"
        }

        func toModel() -> TriviaQuestion {
            TriviaQuestion(id: id, category: category, question: question, options: options, correctAnswer: correctAnswer, explanation: explanation, difficulty: difficulty, active: active)
        }
    }

    private struct MoreLikelyPromptRow: Decodable {
        var id: UUID
        var prompt: String
        var active: Bool

        func toModel() -> MoreLikelyPrompt { MoreLikelyPrompt(id: id, prompt: prompt, active: active) }
    }

    private struct ThisOrThatPromptRow: Decodable {
        var id: UUID
        var optionA: String
        var optionB: String
        var active: Bool

        enum CodingKeys: String, CodingKey {
            case id, active
            case optionA = "option_a"
            case optionB = "option_b"
        }

        func toModel() -> ThisOrThatPrompt { ThisOrThatPrompt(id: id, optionA: optionA, optionB: optionB, active: active) }
    }

    private struct DiscussionTopicRow: Decodable {
        var id: UUID
        var topic: String
        var active: Bool

        func toModel() -> DiscussionTopic { DiscussionTopic(id: id, topic: topic, active: active) }
    }

    struct GameSessionDetail {
        var session: GameSession
        var rounds: [GameSessionRound]
        /// Keyed by `game_session_rounds.content_id`, resolved against whichever content table
        /// matches the session's game type.
        var content: [UUID: GameRoundContent]
        /// Whatever's currently visible to the caller — their own responses always; their
        /// partner's only once both have answered the same round (enforced by RLS, not by
        /// this client filtering anything out).
        var responses: [GameResponse]
    }

    static func startGameSession(gameType: GameType) async throws -> UUID {
        struct Params: Encodable {
            var pGameType: String
            enum CodingKeys: String, CodingKey { case pGameType = "p_game_type" }
        }
        let id: UUID = try await supabase
            .rpc("start_game_session", params: Params(pGameType: gameType.rawValue))
            .execute()
            .value
        return id
    }

    static func abandonGameSession(id: UUID) async throws {
        struct Params: Encodable {
            var pSessionId: UUID
            enum CodingKeys: String, CodingKey { case pSessionId = "p_session_id" }
        }
        try await supabase.rpc("abandon_game_session", params: Params(pSessionId: id)).execute()
    }

    static func markDiscussionRound(roundID: UUID, status: DiscussionRoundStatus) async throws {
        struct Params: Encodable {
            var pRoundId: UUID
            var pStatus: String
            enum CodingKeys: String, CodingKey {
                case pRoundId = "p_round_id"
                case pStatus = "p_status"
            }
        }
        try await supabase.rpc("mark_discussion_round", params: Params(pRoundId: roundID, pStatus: status.rawValue)).execute()
    }

    /// Relies on RLS to scope results to the caller's own couple — no couple id is passed or
    /// needed client-side.
    static func fetchGameSessions(status: GameSessionStatus? = nil) async throws -> [GameSession] {
        var query = supabase.from("game_sessions").select()
        if let status {
            query = query.eq("status", value: status.rawValue)
        }
        let rows: [GameSessionRow] = try await query.order("updated_at", ascending: false).execute().value
        return rows.map { $0.toModel() }
    }

    static func fetchGameSession(id: UUID) async throws -> GameSessionDetail {
        let sessionRow: GameSessionRow = try await supabase
            .from("game_sessions")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        let session = sessionRow.toModel()

        let roundRows: [GameSessionRoundRow] = try await supabase
            .from("game_session_rounds")
            .select()
            .eq("session_id", value: id)
            .order("round_number")
            .execute()
            .value
        let rounds = roundRows.map { $0.toModel() }

        let responseRows: [GameResponseRow] = try await supabase
            .from("game_responses")
            .select()
            .eq("session_id", value: id)
            .execute()
            .value
        let responses = responseRows.map { $0.toModel() }

        let content = try await resolveContent(gameType: session.gameType, contentIDs: rounds.map(\.contentID))

        return GameSessionDetail(session: session, rounds: rounds, content: content, responses: responses)
    }

    private static func resolveContent(gameType: GameType, contentIDs: [UUID]) async throws -> [UUID: GameRoundContent] {
        let unique = Array(Set(contentIDs))
        guard !unique.isEmpty else { return [:] }
        switch gameType {
        case .travelTrivia:
            let rows: [TriviaQuestionRow] = try await supabase.from("trivia_questions").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.trivia($0.toModel())) })
        case .moreLikely:
            let rows: [MoreLikelyPromptRow] = try await supabase.from("more_likely_prompts").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.moreLikely($0.toModel())) })
        case .thisOrThat:
            let rows: [ThisOrThatPromptRow] = try await supabase.from("this_or_that_prompts").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.thisOrThat($0.toModel())) })
        case .discussBeforeTravelling:
            let rows: [DiscussionTopicRow] = try await supabase.from("discussion_topics").select().in("id", values: unique).execute().value
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, GameRoundContent.discuss($0.toModel())) })
        }
    }

    static func submitGameResponse(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool? = nil) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("game_responses")
            .insert(
                GameResponseInsert(
                    sessionId: sessionID,
                    roundNumber: roundNumber,
                    responderId: userID,
                    answer: GameAnswerPayload(value: answerValue),
                    isCorrect: isCorrect
                )
            )
            .execute()
    }

    /// Mirrors `subscribeToFlightUpdates`, but the stream deliberately carries no payload —
    /// per the reveal design, the client always re-fetches via the RLS-protected select on any
    /// change rather than trusting realtime payload contents for sensitive round data.
    static func subscribeToGameSession(id: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        let channel = supabase.channel("game_session_\(id.uuidString)")
        let responseInsertions = channel.postgresChange(InsertAction.self, table: "game_responses", filter: .eq("session_id", value: id.uuidString))
        let sessionUpdates = channel.postgresChange(UpdateAction.self, table: "game_sessions", filter: .eq("id", value: id.uuidString))

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            async let insertionsTask: Void = {
                for await _ in responseInsertions { continuation.yield(()) }
            }()
            async let updatesTask: Void = {
                for await _ in sessionUpdates { continuation.yield(()) }
            }()
            _ = await (insertionsTask, updatesTask)
            continuation.finish()
        }
        return (channel, stream)
    }

    // MARK: - Couple-activity notifications (drawing/trip/memory/game — not flight-specific)

    enum CoupleNotificationEvent: String {
        case drawingSaved = "drawing_saved"
        case tripAdded = "trip_added"
        case memoryAdded = "memory_added"
        case gameStarted = "game_started"
        case gameResultsReady = "game_results_ready"
        case gameReminder = "game_reminder"
    }

    /// Tells the caller's partner (if any) about something the caller just did — best-effort,
    /// never throws. Called right after a real, synced write succeeds (never for a
    /// pending/local-only trip or memory added before pairing), since notifying about
    /// something that doesn't exist in the partner's own view yet would be misleading.
    static func notifyPartner(event: CoupleNotificationEvent, detail: String? = nil) async {
        guard let accessToken = currentAccessToken else { return }
        var body: [String: Any] = ["eventType": event.rawValue]
        if let detail { body["detail"] = detail }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/notify-couple-event"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        _ = try? await URLSession.shared.data(for: request)
    }

    struct CoupleNotificationPreferences {
        var partnerDrawingSaved: Bool
        var partnerTripAdded: Bool
        var partnerMemoryAdded: Bool
        var partnerGameStarted: Bool
        var partnerGameResultsReady: Bool

        static let allEnabled = CoupleNotificationPreferences(
            partnerDrawingSaved: true, partnerTripAdded: true, partnerMemoryAdded: true,
            partnerGameStarted: true, partnerGameResultsReady: true
        )
    }

    private struct CoupleNotificationPreferencesRow: Codable {
        var profileId: UUID
        var partnerDrawingSaved: Bool
        var partnerTripAdded: Bool
        var partnerMemoryAdded: Bool
        var partnerGameStarted: Bool
        var partnerGameResultsReady: Bool

        enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
            case partnerDrawingSaved = "partner_drawing_saved"
            case partnerTripAdded = "partner_trip_added"
            case partnerMemoryAdded = "partner_memory_added"
            case partnerGameStarted = "partner_game_started"
            case partnerGameResultsReady = "partner_game_results_ready"
        }
    }

    /// No row yet means "everything on" — matches the table's own column defaults, same
    /// fallback `notify-couple-event` uses server-side.
    static func fetchCoupleNotificationPreferences() async throws -> CoupleNotificationPreferences {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [CoupleNotificationPreferencesRow] = try await supabase
            .from("notification_preferences")
            .select()
            .eq("profile_id", value: userID)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return .allEnabled }
        return CoupleNotificationPreferences(
            partnerDrawingSaved: row.partnerDrawingSaved,
            partnerTripAdded: row.partnerTripAdded,
            partnerMemoryAdded: row.partnerMemoryAdded,
            partnerGameStarted: row.partnerGameStarted,
            partnerGameResultsReady: row.partnerGameResultsReady
        )
    }

    static func upsertCoupleNotificationPreferences(_ prefs: CoupleNotificationPreferences) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let row = CoupleNotificationPreferencesRow(
            profileId: userID,
            partnerDrawingSaved: prefs.partnerDrawingSaved,
            partnerTripAdded: prefs.partnerTripAdded,
            partnerMemoryAdded: prefs.partnerMemoryAdded,
            partnerGameStarted: prefs.partnerGameStarted,
            partnerGameResultsReady: prefs.partnerGameResultsReady
        )
        try await supabase
            .from("notification_preferences")
            .upsert(row, onConflict: "profile_id")
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
