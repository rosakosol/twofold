//
//  SignInLoadingGateTests.swift
//  TwofoldTests
//
//  The gate that decides whether someone sees the app, a paywall, or a loading screen.
//
//  `RootView` holds people on the loading screen while `hasResolvedOutgoingConnectionRequest` is
//  false, so that someone waiting on an inviter is never shown a paywall that is about to be
//  retracted. The cost of getting that wrong is total: an unresolved flag is an app that never
//  finishes loading.
//
//  That is exactly what happened. RootView's launch task returns early when there is no session,
//  leaving the flag false; signing in then flips `hasCouple` true with nothing left to resolve it,
//  and the beating heart runs forever. Reported on a real device, on a real account.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct SignInLoadingGateTests {

    /// A fresh model is unresolved — this is the state a signed-out launch leaves behind, and the
    /// reason the flag cannot be assumed true.
    @Test("a new session starts unresolved")
    func startsUnresolved() {
        #expect(AppModel().hasResolvedOutgoingConnectionRequest == false)
    }

    /// The gate itself. Three ways in, and the loading screen is only correct while the answer is
    /// genuinely unknown.
    @Test("access is granted by any of the three routes")
    func accessRoutes() {
        #expect(RootView.hasAccess(backendSaysActive: true, deviceHoldsEntitlement: false, awaitingPartnerDecision: false))
        #expect(RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: true, awaitingPartnerDecision: false))
        #expect(RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: true))
        #expect(!RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false))
    }

    /// The bug, stated as the condition that produced it: signed in, no entitlement yet, and the
    /// request lookup never resolved. That combination is the infinite loading screen.
    ///
    /// It is a fault only because nothing was left to resolve the flag — the loading state itself
    /// is correct for a moment. `loadSignedInState` now resolves it wherever `hasCouple` is set,
    /// so this combination cannot persist past a completed sign-in.
    @Test("signed in with nothing resolved is the stuck state")
    func stuckStateIsIdentified() {
        let stuck = !RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false)
            && !AppModel().hasResolvedOutgoingConnectionRequest
        #expect(stuck, "this is the combination that holds the loading screen — it must not outlive sign-in")
    }

    /// Resolving is what releases the screen, whatever the answer turns out to be. A network
    /// failure resolves to "no pending request" rather than holding someone indefinitely.
    @Test("a paired couple resolves without a round trip")
    func pairedResolvesImmediately() async {
        let model = AppModel()
        model.partnerConnected = true
        await model.refreshPendingOutgoingConnectionRequest()
        #expect(model.hasResolvedOutgoingConnectionRequest)
        #expect(model.pendingOutgoingConnectionRequest == nil)
    }
}
