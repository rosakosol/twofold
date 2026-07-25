//
//  OnboardingModel.swift
//  Twofold
//
//  Everything collected across the registration/onboarding flow, before it gets
//  folded into the real AppModel state via `AppModel.completeOnboarding`.
//

import Foundation
import Observation

@Observable
final class OnboardingModel {
    var path: [OnboardingStep] = []
    var role: OnboardingRole = .inviter

    // Account
    var firstName: String = ""
    var email: String = ""
    var password: String = ""

    // Home city
    var homeCity: Place?

    // Partner connection
    var inviteCode: String?
    var inviterName: String?
    var inviterAvatarURL: URL?
    /// True once account creation has happened — lets `EnterPartnerCodeView` decide
    /// whether it still needs to route through account creation or can connect directly.
    var hasAccount: Bool = false

    // Next trip
    var draftedTrip: Trip?

    // MARK: - New default onboarding flow (situation → ... → save account)
    //
    // Everything below accumulates purely locally — account creation now happens at the
    // very end of the flow (`SaveAccountView`), so none of this can be persisted to
    // Supabase until then. `AppModel.completeOnboarding` is the single place it all gets
    // applied, in one shot, once a real session exists.

    var situation: RelationshipSituation?
    var frequency: TravelFrequency?
    var attribution: AttributionSource?
    var goals: Set<OnboardingGoal> = []

    /// The partner's name/city as *typed by this user* — personalization only, not a real
    /// linked account. Real pairing still happens via the existing invite-code flow, later,
    /// from the home screen's setup checklist.
    var partnerName: String = ""
    var partnerCity: Place?
    var anniversaryDate: Date?

    var userGender: Gender?
    var partnerGender: Gender?

    /// The word later screens use in place of the generic "their" when referring to the
    /// partner by name — "his"/"her" for a selected gender, or "their" as a safe default if
    /// gender was never asked/answered.
    var partnerPossessive: String {
        partnerGender?.possessive ?? "their"
    }

    /// Picked photos held as raw JPEG data until account creation succeeds — there's no
    /// session to upload against until then. `partnerPhotoData` is just this user's
    /// placeholder guess of their partner's photo (stored as this user's own
    /// `partner_avatar_path`, not the partner's `avatar_path`).
    var selfPhotoData: Data?
    var partnerPhotoData: Data?

    /// Set once the user has responded to the system notification prompt (either way) —
    /// lets the app avoid ever re-prompting.
    var notificationsGranted: Bool?

    var draftedFlightNumber: String?
    var draftedFlightDate: Date?

    /// Cache backing `illustrativeOriginCity`, picked once and reused so the notifications
    /// and Live Activity sell screens show the same made-up departure city as each other.
    private var cachedIllustrativeOriginCity: Place?

    /// The illustrative departure city used by the notification/Live Activity sell screens'
    /// example flight (partner's city → user's city, matching the "reunion" framing used
    /// throughout onboarding) — unless the couple lives in the same city, which would make
    /// that example flight depart and arrive in the same place. In that case a random other
    /// city stands in instead, chosen once and cached so both screens agree on the same one.
    var illustrativeOriginCity: Place? {
        guard let homeCity, let partnerCity else { return partnerCity }
        guard homeCity.city == partnerCity.city && homeCity.country == partnerCity.country else {
            return partnerCity
        }
        if cachedIllustrativeOriginCity == nil {
            cachedIllustrativeOriginCity = Place.commonCities.filter { $0.city != homeCity.city }.randomElement()
        }
        return cachedIllustrativeOriginCity
    }

    /// Called when a sign-in attempt anywhere in onboarding (or the returning-user sign-in
    /// sheet) resolves to a previously-deleted account — see `BackendError.accountDeleted`.
    /// A full wipe back to a brand-new `OnboardingModel()`'s defaults, not just the account
    /// fields — every questionnaire answer collected so far gets discarded too, so this is a
    /// genuinely fresh flow rather than one that quietly remembers anything about the previous
    /// attempt. `path = []` also pops all the way back to `WelcomeView`, the root of
    /// `OnboardingCoordinatorView`'s NavigationStack.
    func resetAfterDeletedAccount() {
        path = []
        role = .inviter

        firstName = ""
        email = ""
        password = ""

        homeCity = nil

        inviteCode = nil
        inviterName = nil
        inviterAvatarURL = nil
        hasAccount = false

        draftedTrip = nil

        situation = nil
        frequency = nil
        attribution = nil
        goals = []

        partnerName = ""
        partnerCity = nil
        anniversaryDate = nil

        userGender = nil
        partnerGender = nil

        selfPhotoData = nil
        partnerPhotoData = nil

        notificationsGranted = nil

        draftedFlightNumber = nil
        draftedFlightDate = nil

        cachedIllustrativeOriginCity = nil
    }

    func resetForNewInvite(code: String) {
        role = .invitee
        inviteCode = code
        path = [.joinInvite]
        // `get_invite_code_inviter_info` deliberately works without an authenticated session
        // (see its migration's own comment) specifically so this — a cold deep-link tap, before
        // any account exists — can show the real inviter on JoinInviteView. Fired async rather
        // than blocking the navigation above; JoinInviteView just updates once this resolves.
        Task {
            let info = try? await BackendService.inviterInfo(forCode: code)
            inviterName = info?.name
            inviterAvatarURL = info?.avatarURL
        }
    }
}
