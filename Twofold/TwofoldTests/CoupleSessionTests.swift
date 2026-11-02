//
//  CoupleSessionTests.swift
//  TwofoldTests
//
//  The couple and onboarding store, and that reset() puts it back to a signed-out device.
//

import Foundation
import Testing
@testable import Twofold

@Suite("CoupleSession")
@MainActor
struct CoupleSessionTests {

    @Test("reset() forgets the couple, onboarding, the invite and the requests")
    func resetClearsEverything() {
        let session = CoupleSession()
        session.hasCouple = true
        session.needsOnboarding = true
        session.hasSavedOnboardingProgress = true
        session.couple.partnerB.name = "Alex"
        session.partnerConnected = true
        session.inviteCode = "ABC123"
        session.hasLoadedCoupleState = true
        session.backendCoupleID = UUID()

        session.reset()

        #expect(session.hasCouple == false)
        #expect(session.needsOnboarding == false)
        #expect(session.hasSavedOnboardingProgress == false)
        #expect(session.couple.partnerB.name == "Partner")
        #expect(session.couple.partnerA.name == "You")
        #expect(session.partnerConnected == false)
        #expect(session.inviteCode == nil)
        #expect(session.hasLoadedCoupleState == false)
        #expect(session.backendCoupleID == nil)
        #expect(session.pendingConnectionRequests.isEmpty)
        #expect(session.pendingOutgoingConnectionRequest == nil)
    }
}
