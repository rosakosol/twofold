//
//  BackendService+Profile.swift
//  Twofold
//
//  The signed-in person's own profile: name, home city, partner nickname and city, birthday,
//  anniversary, one-off flags, and avatars.
//

import Foundation
import Supabase

extension BackendService {

    private struct FirstNameUpdate: Encodable {
        var firstName: String
        enum CodingKeys: String, CodingKey { case firstName = "first_name" }
    }

    private struct OnboardingCompletedUpdate: Encodable {
        var onboardingCompletedAt: String
        enum CodingKeys: String, CodingKey { case onboardingCompletedAt = "onboarding_completed_at" }
    }

    /// Called once, by `AppModel.finishOnboarding()`. Until this lands, `fetchOwnProfile` keeps
    /// reporting `hasCompletedOnboarding == false` and every launch routes back into onboarding —
    /// so this is the one write in the flow that must not be swallowed by a `try?` at the call site
    /// without the caller knowing it failed.
    static func markOnboardingCompleted() async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(OnboardingCompletedUpdate(onboardingCompletedAt: ISO8601DateFormatter().string(from: .now)))
            .eq("id", value: userID)
            .execute()
    }

    private struct OnboardingAccountCreatedUpdate: Encodable {
        var onboardingAccountCreatedAt: String?
        enum CodingKeys: String, CodingKey { case onboardingAccountCreatedAt = "onboarding_account_created_at" }
    }

    /// Records that in-app onboarding created this account — written by `applyOnboardingAccount`,
    /// at the same moment it writes everything the questionnaire collected, because that is
    /// precisely the boundary this timestamp is describing.
    ///
    /// Not swallowed at the call site for the same reason `markOnboardingCompleted` is not: a lost
    /// write here does not break anything, it just costs somebody the whole questionnaire again.
    static func markOnboardingAccountCreated() async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(OnboardingAccountCreatedUpdate(onboardingAccountCreatedAt: ISO8601DateFormatter().string(from: .now)))
            .eq("id", value: userID)
            .execute()
    }

    static func updateFirstName(_ name: String) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(FirstNameUpdate(firstName: name))
            .eq("id", value: userID)
            .execute()
    }

    private struct DeviceContextUpdate: Encodable {
        var timezone: String
        var locale: String
    }

    /// Reports the two things about this device the server cannot work out for itself.
    ///
    /// `timezone` is the IANA identifier the daily question and streak use to decide when "today"
    /// ends — see 20260908000000_local_midnight_day_boundary.sql.
    ///
    /// `locale` is the language to compose server-sent copy in. Every push this app sends is
    /// written in an edge function, which has no other way to know what the recipient reads; see
    /// 20261011000200_profile_locale.sql. Nothing reads it yet — it is reported now so that when
    /// something does, the column is already filled in for everyone who has opened the app since,
    /// rather than having to be guessed at retrospectively.
    ///
    /// Best-effort (`try?` at the call site): a failure just means the server keeps the previously
    /// reported values rather than blocking launch.
    ///
    /// Written on every foreground rather than once, deliberately. For the timezone that is the
    /// whole point — it has to follow someone who travels. For the locale it matters less often but
    /// costs nothing, and someone changing their phone's language is exactly the moment the stored
    /// value would otherwise go stale and stay stale.
    static func updateDeviceContext() async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(DeviceContextUpdate(
                timezone: TimeZone.current.identifier,
                // The full BCP 47 identifier, region included ("en-AU", "pt-BR"), rather than just
                // the language code. Narrowing it here would throw away the information about what
                // people actually want before anybody has looked at it.
                locale: Locale.current.identifier(.bcp47)
            ))
            .eq("id", value: userID)
            .execute()
    }

    /// Marks this account as used right now, which is the only thing keeping the dormancy timer
    /// (20261029000100) from eventually closing it.
    ///
    /// This has to exist because `auth.users.last_sign_in_at` does not mean "last used" — it is
    /// stamped on an actual sign-in, not on the token refreshes that keep somebody signed in for
    /// years. Without this call the server would see every long-standing account as untouched
    /// since the day it was created.
    static func touchLastActive() async throws {
        try await supabase.rpc("touch_last_active").execute()
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
        var subscriptionTier: String?
        /// Where this account's own subscription was bought — `profiles.subscription_store`, written
        /// by `revenuecat-webhook`. See `AppModel.viewerSubscriptionStore` for why it is only ever
        /// read as the viewer's own and never as the couple's.
        var subscriptionStore: String?
        var partnerConnectedCelebrationShown: Bool
        var setupChecklistDismissed: Bool
        /// Non-nil only while there's an unacknowledged "your subscription lapsed because {name}
        /// left" notice to show — see `leave_couple`'s partner_subscription_lapse_* columns and
        /// `AppModel.partnerSubscriptionLapsedPartnerName`.
        var partnerSubscriptionLapsePartnerName: String?
        var partnerSubscriptionLapseShown: Bool
        /// False only for an account created outside the app — today that means a website
        /// subscription, which produces a real `auth.users` row and a `profiles` row (via
        /// `handle_new_user`) without any of the things onboarding collects. `AppModel
        /// .loadSignedInState` routes these into onboarding instead of admitting them to the app
        /// nameless. See migration 20261106000000.
        var hasCompletedOnboarding: Bool
        /// In-app onboarding got as far as creating this account, at `.saveAccount` — so the
        /// questionnaire is answered and only the invite/trial/paywall screens are outstanding.
        /// False for a website account, which answered nothing. See migration 20261110001200.
        var hasSavedOnboardingProgress: Bool
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
            avatarURL: await avatarSignedURLOrNil(profile.avatarPath),
            birthday: Birthday(month: profile.birthdayMonth, day: profile.birthdayDay),
            timeZoneIdentifier: profile.timezone
        )

        return OwnProfileState(
            person: person,
            partnerName: profile.partnerName,
            partnerHomeCity: profile.partnerHomePlaceId.flatMap { places[$0] },
            partnerAvatarURL: await avatarSignedURLOrNil(profile.partnerAvatarPath),
            anniversaryDate: profile.anniversaryDate.flatMap { Self.dateOnlyFormatter.date(from: $0) },
            subscriptionActive: profile.subscriptionActive,
            subscriptionTier: profile.subscriptionTier,
            subscriptionStore: profile.subscriptionStore,
            partnerConnectedCelebrationShown: profile.partnerConnectedCelebrationShown,
            setupChecklistDismissed: profile.setupChecklistDismissed,
            partnerSubscriptionLapsePartnerName: profile.partnerSubscriptionLapsePartnerName,
            partnerSubscriptionLapseShown: profile.partnerSubscriptionLapseShown,
            hasCompletedOnboarding: profile.onboardingCompletedAt != nil,
            hasSavedOnboardingProgress: profile.onboardingAccountCreatedAt != nil
        )
    }

    // MARK: - Profile / home city

    struct ProfileRow: Decodable {
        var id: UUID
        var firstName: String
        var homePlaceId: UUID?
        var avatarPath: String?
        var partnerAvatarPath: String?
        var partnerName: String?
        var partnerHomePlaceId: UUID?
        var anniversaryDate: String?
        var subscriptionActive: Bool
        var subscriptionTier: String?
        /// "app_store", "rc_billing", "stripe", "promotional"… — migration 20261109000500. Null for
        /// anyone whose last webhook predates the column, which is why every reader treats nil as
        /// "we don't know" rather than as a default.
        var subscriptionStore: String?
        var partnerConnectedCelebrationShown: Bool
        var setupChecklistDismissed: Bool
        var partnerSubscriptionLapsePartnerName: String?
        var partnerSubscriptionLapseShown: Bool
        /// Decoded as the raw string rather than a Date: nothing needs the instant, only whether
        /// there is one, and Postgres timestamptz comes back with a microsecond precision that
        /// Foundation's ISO8601 decoding rejects outright.
        var onboardingCompletedAt: String?
        /// Same raw-string treatment, same reason. See migration 20261110001200.
        var onboardingAccountCreatedAt: String?
        /// Month and day, no year — migration 20261110001300. Both null together.
        var birthdayMonth: Int?
        var birthdayDay: Int?
        /// IANA identifier, written on every foreground by `updateDeviceContext`. Read here so a
        /// birthday can be judged where its owner actually is — see `Person.isBirthdayToday`.
        var timezone: String?

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
            case subscriptionTier = "subscription_tier"
            case subscriptionStore = "subscription_store"
            case partnerConnectedCelebrationShown = "partner_connected_celebration_shown"
            case setupChecklistDismissed = "setup_checklist_dismissed"
            case partnerSubscriptionLapsePartnerName = "partner_subscription_lapse_partner_name"
            case partnerSubscriptionLapseShown = "partner_subscription_lapse_shown"
            case onboardingCompletedAt = "onboarding_completed_at"
            case onboardingAccountCreatedAt = "onboarding_account_created_at"
            case birthdayMonth = "birthday_month"
            case birthdayDay = "birthday_day"
            case timezone
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

    private struct PartnerConnectedCelebrationUpdate: Encodable {
        var partnerConnectedCelebrationShown = true
        enum CodingKeys: String, CodingKey { case partnerConnectedCelebrationShown = "partner_connected_celebration_shown" }
    }

    /// Marks the "you and your partner are connected" reveal as shown, server-side — a plain
    /// UserDefaults flag here would reset every time someone reinstalls the app, showing the
    /// celebration again even though nothing about their account changed. Best-effort: worst
    /// case on failure is the celebration shows once more next launch, not worth surfacing an
    /// error for.
    static func markPartnerConnectedCelebrationShown() async {
        guard let userID = currentUserID else { return }
        _ = try? await supabase
            .from("profiles")
            .update(PartnerConnectedCelebrationUpdate())
            .eq("id", value: userID)
            .execute()
    }

    private struct SubscriptionLapseNoticeShownUpdate: Encodable {
        var partnerSubscriptionLapseShown = true
        enum CodingKeys: String, CodingKey { case partnerSubscriptionLapseShown = "partner_subscription_lapse_shown" }
    }

    /// Same reasoning as `markPartnerConnectedCelebrationShown` — acknowledging "your
    /// subscription lapsed because {name} left" needs to survive a reinstall. Re-armable: if
    /// `leave_couple` sets this back to `false` again later (a new relationship, same non-payer
    /// outcome), this simply gets called again.
    static func markPartnerSubscriptionLapseShown() async {
        guard let userID = currentUserID else { return }
        _ = try? await supabase
            .from("profiles")
            .update(SubscriptionLapseNoticeShownUpdate())
            .eq("id", value: userID)
            .execute()
    }

    private struct SetupChecklistDismissedUpdate: Encodable {
        var setupChecklistDismissed = true
        enum CodingKeys: String, CodingKey { case setupChecklistDismissed = "setup_checklist_dismissed" }
    }

    /// Same reasoning as `markPartnerConnectedCelebrationShown` — the Home screen's "Finish
    /// setting up Twofold" card dismissal needs to survive a reinstall, not just live in
    /// UserDefaults.
    static func markSetupChecklistDismissed() async {
        guard let userID = currentUserID else { return }
        _ = try? await supabase
            .from("profiles")
            .update(SetupChecklistDismissedUpdate())
            .eq("id", value: userID)
            .execute()
    }

    private struct SetupChecklistResetUpdate: Encodable {
        var setupChecklistDismissed = false
        enum CodingKeys: String, CodingKey { case setupChecklistDismissed = "setup_checklist_dismissed" }
    }

    /// Re-shows the setup checklist after someone removes their partner — they're genuinely
    /// back in the same unpaired state a brand-new user starts in, and need that same nudge
    /// again even if they'd already dismissed it once during their original onboarding.
    static func resetSetupChecklistDismissed() async {
        guard let userID = currentUserID else { return }
        _ = try? await supabase
            .from("profiles")
            .update(SetupChecklistResetUpdate())
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

    private struct BirthdayUpdate: Encodable {
        var birthdayMonth: Int?
        var birthdayDay: Int?
        enum CodingKeys: String, CodingKey {
            case birthdayMonth = "birthday_month"
            case birthdayDay = "birthday_day"
        }
    }

    /// Sets or clears this person's own birthday. Nil clears both halves, which is what "remove
    /// it" means — the column pair is all-or-nothing by check constraint, and giving one is always
    /// optional.
    ///
    /// Only ever your own row, like every other write here: a birthday is a fact about its owner,
    /// and the partner reads it through `profiles_select_self_or_partner` rather than being given
    /// a way to author it.
    static func updateBirthday(_ birthday: Birthday?) async throws {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        try await supabase
            .from("profiles")
            .update(BirthdayUpdate(birthdayMonth: birthday?.month, birthdayDay: birthday?.day))
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

    /// `avatars` is a private bucket (see `20260722010000_private_avatars_drawing_pads.sql` —
    /// it used to be public, meaning anyone who ever obtained a profile/couple UUID could view
    /// that photo forever, unauthenticated, with no revocation possible). Every read now goes
    /// through a signed URL instead, scoped by storage RLS to: the owner themself, their
    /// current partner, the other party to a pending connection request, or — for the
    /// pre-auth invite-preview screens — anyone while that profile has a pending invite code
    /// outstanding (mirrors the same narrow pre-auth exposure `get_invite_code_inviter_info`
    /// already establishes for the inviter's name).
    static func avatarSignedURL(path: String) async throws -> URL {
        try await R2Storage.readURL(.avatar, path: path)
    }

    /// Convenience for the common `path.flatMap { ... }` shape used all over this file — Optional
    /// has no async `flatMap`, so callers used to reach for the (synchronous, public-URL) helper
    /// directly. Swallows a signing failure to nil rather than throwing, same as a missing path.
    static func avatarSignedURLOrNil(_ path: String?) async -> URL? {
        guard let path else { return nil }
        return try? await avatarSignedURL(path: path)
    }

    /// Uploads the signed-in user's profile photo (JPEG data), points their profile at it,
    /// and returns a signed URL for immediate local use. Every re-upload overwrites the same
    /// deterministic path (`{userID}/avatar.jpg`), so unlike the old public-URL scheme there's no
    /// separate cache-busting step needed — each signed URL embeds its own unique token/expiry,
    /// so it's never the same string twice.
    @discardableResult
    static func uploadAvatar(imageData: Data) async throws -> URL {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let path = "\(userID)/avatar.jpg"

        try await R2Storage.upload(.avatar, path: path, data: imageData, contentType: "image/jpeg")

        try await supabase
            .from("profiles")
            .update(AvatarPathUpdate(avatarPath: path))
            .eq("id", value: userID)
            .execute()

        guard let url = try? await avatarSignedURL(path: path) else { throw BackendError.avatarURLFailed }
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

        try await R2Storage.upload(.avatar, path: path, data: imageData, contentType: "image/jpeg")

        try await supabase
            .from("profiles")
            .update(PartnerAvatarPathUpdate(partnerAvatarPath: path))
            .eq("id", value: userID)
            .execute()

        guard let url = try? await avatarSignedURL(path: path) else { throw BackendError.avatarURLFailed }
        return url
    }
}
