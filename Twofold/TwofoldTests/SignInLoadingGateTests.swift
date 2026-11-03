//
//  SignInLoadingGateTests.swift
//  TwofoldTests
//
//  `hasResolvedOutgoingConnectionRequest` after sign-in.
//
//  The app used to hold people on the loading screen while that flag was false, and RootView's
//  launch task returns early when there is no session, leaving it false; signing in then flipped
//  `hasCouple` true with nothing left to resolve it, and the beating heart ran forever. Reported on
//  a real device, on a real account. What is pinned here is that the flag does get resolved.
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
