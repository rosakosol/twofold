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
    var isPartnerConnected: Bool = false
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

    /// Ordered steps of the default "Get started" flow, used to drive the progress bar.
    /// `.frequency` is sometimes skipped (haven't-met-yet couples), so progress is computed
    /// by position in this canonical list, not by raw `path.count`.
    static let defaultFlowSteps: [OnboardingStep] = [
        .situation, .frequency, .attribution, .goals, .yourName, .partnerName,
        .benchmark, .coupleLocations, .personalizedInsight, .notificationsSell,
        .liveActivitySell, .addFirstFlight, .twofoldPreview, .trialTrust,
        .paywall, .purchaseSuccess, .saveAccount,
    ]

    /// 0...1 progress through the default onboarding flow, or nil when the current step
    /// isn't part of it (e.g. the preserved deep-link invite path), so those screens simply
    /// don't show a progress bar at all.
    var progress: Double? {
        guard let currentStep = path.last,
              let index = Self.defaultFlowSteps.firstIndex(of: currentStep) else { return nil }
        return Double(index + 1) / Double(Self.defaultFlowSteps.count)
    }

    func resetForNewInvite(code: String) {
        role = .invitee
        inviteCode = code
        inviterName = InviteCode.inviterName(from: code)
        path = [.joinInvite]
    }
}
