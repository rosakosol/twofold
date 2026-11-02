//
//  OnboardingResume.swift
//  Twofold
//
//  Where "Pick up where you left off" goes, for somebody who made an account and stopped.
//

import Foundation

/// An invite code an invitee had in hand when their account was made, kept on this device until
/// it has been redeemed.
struct SavedInvite: Codable, Equatable {
    var code: String
    /// `BackendService.InviteOrigin`'s raw value.
    var origin: String

    var inviteOrigin: BackendService.InviteOrigin {
        BackendService.InviteOrigin(rawValue: origin) ?? .code
    }
}

enum OnboardingResume {
    enum Plan: Equatable {
        /// The inviter's tail: invite your partner, then the trial and paywall.
        case inviter
        /// An invitee whose request is with the inviter. The rest of the invitee flow.
        case inviteeAwaitingReply(inviterName: String)
        /// An invitee who had a code and had not redeemed it yet.
        case inviteeToRedeem(SavedInvite)
    }

    /// A request already sent outranks a saved code: it is what the code turned into.
    static func plan(pendingRequestInviterName: String?, savedInvite: SavedInvite?) -> Plan {
        if let pendingRequestInviterName { return .inviteeAwaitingReply(inviterName: pendingRequestInviterName) }
        if let savedInvite { return .inviteeToRedeem(savedInvite) }
        return .inviter
    }

    /// Puts the onboarding model where `plan` says to carry on from.
    static func apply(_ plan: Plan, to onboarding: OnboardingModel) {
        switch plan {
        case .inviter:
            onboarding.role = .inviter
            onboarding.path = [.invitePartner]
        case .inviteeAwaitingReply(let inviterName):
            onboarding.role = .invitee
            onboarding.inviterName = inviterName
            onboarding.hasResolvedInviterName = true
            onboarding.hasAccount = true
            // The photo step and the rest of the invitee tail. The request exists, so the screen
            // after the photo is the one that says it was sent.
            onboarding.connectedOnRedeem = false
            onboarding.path = [.addPhoto]
        case .inviteeToRedeem(let invite):
            onboarding.role = .invitee
            onboarding.inviteCode = invite.code
            onboarding.inviteOrigin = invite.inviteOrigin
            onboarding.hasAccount = true
            // Home City is the step that redeems.
            onboarding.path = [.homeCity]
            Task { await onboarding.resolveInviter(code: invite.code) }
        }
    }

    // MARK: - The saved code

    static func key(for userID: UUID) -> String {
        "onboardingSavedInvite.\(userID.uuidString)"
    }

    static func save(_ invite: SavedInvite, for userID: UUID) {
        guard let data = try? JSONEncoder().encode(invite) else { return }
        UserDefaults.standard.set(data, forKey: key(for: userID))
    }

    static func savedInvite(for userID: UUID) -> SavedInvite? {
        guard let data = UserDefaults.standard.data(forKey: key(for: userID)) else { return nil }
        return try? JSONDecoder().decode(SavedInvite.self, from: data)
    }

    static func clear(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userID))
    }
}
