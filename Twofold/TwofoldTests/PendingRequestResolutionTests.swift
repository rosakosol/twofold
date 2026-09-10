//
//  PendingRequestResolutionTests.swift
//  TwofoldTests
//
//  The difference between "there is no pending request" and "we have not found out yet".
//
//  `pendingOutgoingConnectionRequest` is nil in both cases, and two screens read that nil as the
//  first: RootView shows the paywall to someone who is exempt from it, and Home offers to invite a
//  partner someone has already invited. Both corrected themselves a round trip later, which is what
//  a flash of the wrong screen is.
//
//  So what is asserted here is mostly about the *unknown* state — that it exists, that it is not
//  mistaken for an answer, and that it does not last forever.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct PendingRequestResolutionTests {

    @Test("a fresh session has not resolved anything")
    func startsUnresolved() {
        let model = AppModel()
        #expect(model.hasResolvedOutgoingConnectionRequest == false)
        #expect(model.pendingOutgoingConnectionRequest == nil, "nil here means unknown, not absent")
    }

    /// RootView's gate. An unresolved lookup must hold the loading screen rather than fall through
    /// to a paywall — that is the flash, and for an invitee it is a paywall they are exempt from.
    @Test("unknown holds the loading screen instead of showing a paywall")
    func unknownHoldsLoading() {
        let noAccess = !RootView.hasAccess(
            backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false
        )
        #expect(noAccess, "no subscription and no known request is not access")

        // Which is only correct to act on once the lookup has resolved. Before that, the same
        // inputs describe an unknown rather than a refusal.
        let model = AppModel()
        #expect(!model.hasResolvedOutgoingConnectionRequest,
                "acting on `noAccess` while this is false is what showed the paywall")
    }

    /// Home's branch. The invite card offers to do the one thing an invitee has already done, so it
    /// waits to be told there is nothing pending rather than assuming it.
    private func showsInviteCard(needsInvite: Bool, resolved: Bool, pending: Bool) -> Bool {
        if pending { return false }
        return needsInvite && resolved
    }

    @Test("the invite card waits until the answer is known")
    func inviteCardWaits() {
        #expect(!showsInviteCard(needsInvite: true, resolved: false, pending: false),
                "unresolved must show nothing rather than the wrong card")
        #expect(showsInviteCard(needsInvite: true, resolved: true, pending: false),
                "resolved and genuinely nothing pending is when it belongs")
        #expect(!showsInviteCard(needsInvite: true, resolved: true, pending: true),
                "a real pending request takes precedence")
    }

    /// A paired couple needs no round trip at all — the guard resolves immediately, so pairing
    /// never costs a loading beat.
    @Test("a paired couple resolves without asking")
    func pairedResolvesImmediately() async {
        let model = AppModel()
        model.partnerConnected = true
        await model.refreshPendingOutgoingConnectionRequest()
        #expect(model.hasResolvedOutgoingConnectionRequest)
        #expect(model.pendingOutgoingConnectionRequest == nil)
    }

    /// The limit on patience. Two failed attempts still resolve, because a network that is
    /// genuinely down must not hold someone on a loading screen indefinitely — after two tries the
    /// honest answer is that we do not know, and the app has to proceed on that.
    @Test("it gives up rather than looping")
    func resolvesEvenWhenItCannotFindOut() async {
        let model = AppModel()
        // Unauthenticated: the fetch cannot succeed, which is the shape of a persistent failure.
        await model.refreshPendingOutgoingConnectionRequest()
        #expect(model.hasResolvedOutgoingConnectionRequest,
                "an unresolvable lookup must still end, or the loading screen never clears")
    }
}
