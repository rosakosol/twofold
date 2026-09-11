//
//  RedundantSubscriptionTests.swift
//  TwofoldTests
//
//  A couple paying twice for one subscription, on the client side of it.
//
//  The consequence attached to this is asymmetric, and that shapes what is worth asserting. Failing
//  to mention the overlap costs someone a subscription fee they didn't need to pay. Naming the
//  wrong person asks them to cancel something they wanted to keep — and they can't un-cancel it.
//  So the assertions that matter most are the ones about staying quiet: nobody is named on a
//  guess, and only the person who would do the cancelling is offered the button.
//

import Testing
import Foundation
@testable import Twofold

struct RedundantSubscriptionTests {

    private func decode(_ json: String) throws -> BackendService.RedundantSubscription {
        try JSONDecoder().decode(BackendService.RedundantSubscription.self, from: Data(json.utf8))
    }

    /// The RPC returns snake_case, which is the shape that silently produces a struct of defaults
    /// if the keys don't line up.
    @Test("the RPC's row decodes")
    func decodesTheRow() throws {
        let state = try decode(#"{"both_subscribed":true,"redundant_profile_id":"5A1E6C7E-0000-0000-0000-00000000000A","i_am_redundant":true}"#)
        #expect(state.bothSubscribed)
        #expect(state.iAmRedundant)
        #expect(state.redundantProfileID != nil)
    }

    @Test("a couple with one subscription between them is not flagged")
    func noOverlap() throws {
        let state = try decode(#"{"both_subscribed":false,"redundant_profile_id":null,"i_am_redundant":false}"#)
        #expect(!state.bothSubscribed)
        #expect(!state.partnerIsRedundant)
    }

    @Test("the later purchaser is the one asked to cancel")
    func iAmTheLaterPurchaser() throws {
        let state = try decode(#"{"both_subscribed":true,"redundant_profile_id":"5A1E6C7E-0000-0000-0000-00000000000A","i_am_redundant":true}"#)
        #expect(state.iAmRedundant)
        #expect(!state.partnerIsRedundant, "both sides of the couple cannot be the redundant one")
    }

    @Test("the earlier purchaser is told it is their partner")
    func partnerIsTheLaterPurchaser() throws {
        let state = try decode(#"{"both_subscribed":true,"redundant_profile_id":"5A1E6C7E-0000-0000-0000-00000000000B","i_am_redundant":false}"#)
        #expect(!state.iAmRedundant)
        #expect(state.partnerIsRedundant)
    }

    /// The case the whole nil-handling exists for. RevenueCat may not have told us when either
    /// subscription started, so there is no basis for naming one of them — but the overlap is
    /// still real and still worth saying.
    ///
    /// `partnerIsRedundant` must be false here. If it read as "not me, therefore them", this state
    /// would tell someone their partner is wasting money on nothing more than a missing field.
    @Test("nobody is named when the purchase dates can't be compared")
    func nobodyIsNamed() throws {
        let state = try decode(#"{"both_subscribed":true,"redundant_profile_id":null,"i_am_redundant":false}"#)
        #expect(state.bothSubscribed, "the overlap is still reported")
        #expect(!state.iAmRedundant)
        #expect(!state.partnerIsRedundant, "an unknown purchase date must not read as 'it's them'")
    }
}
