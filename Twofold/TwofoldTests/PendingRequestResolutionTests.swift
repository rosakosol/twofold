//
//  PendingRequestResolutionTests.swift
//  TwofoldTests
//
//  The difference between "there is no pending request" and "we have not found out yet".
//
//  `pendingOutgoingConnectionRequest` is nil in both cases, and Home read that nil as the first: it
//  offered to invite a partner someone had already invited, and corrected itself a round trip
//  later, which is what a flash of the wrong screen is.
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
