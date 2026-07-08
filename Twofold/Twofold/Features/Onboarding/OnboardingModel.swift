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

    // Relationship context (inviter only)
    var relationshipStatus: RelationshipStatus?
    var seeingFrequency: SeeingFrequency?

    // Partner connection
    var inviteCode: String?
    var inviterName: String?
    var isPartnerConnected: Bool = false
    /// True once account creation has happened — lets `EnterPartnerCodeView` decide
    /// whether it still needs to route through account creation or can connect directly.
    var hasAccount: Bool = false

    // Next trip
    var draftedTrip: Trip?

    func resetForNewInvite(code: String) {
        role = .invitee
        inviteCode = code
        inviterName = InviteCode.inviterName(from: code)
        path = [.joinInvite]
    }
}
