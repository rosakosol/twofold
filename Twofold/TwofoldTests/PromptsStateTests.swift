//
//  PromptsStateTests.swift
//  TwofoldTests
//
//  The prompts and notices store, and that reset() leaves none of them for the next account.
//

import Foundation
import Testing
@testable import Twofold

@Suite("PromptsState")
@MainActor
struct PromptsStateTests {

    @Test("reset() clears every notice, prompt and seen-it flag")
    func resetClearsEverything() {
        let prompts = PromptsState()
        prompts.partnerDisconnectedMessage = "Your connection with Alex has ended"
        prompts.writeRefusedMessage = "refused"
        prompts.partnerConnectedCelebrationShown = true
        prompts.setupChecklistDismissed = true
        prompts.partnerSubscriptionLapsedPartnerName = "Alex"
        prompts.pendingReviewMilestone = .firstMemory
        prompts.pendingPartnerInviteNudge = true

        prompts.reset()

        #expect(prompts.partnerDisconnectedMessage == nil)
        #expect(prompts.writeRefusedMessage == nil)
        #expect(prompts.partnerConnectedCelebrationShown == false)
        #expect(prompts.setupChecklistDismissed == false)
        #expect(prompts.partnerSubscriptionLapsedPartnerName == nil)
        #expect(prompts.pendingReviewMilestone == nil)
        #expect(prompts.pendingPartnerInviteNudge == false)
    }

    @Test("A milestone already waiting is not replaced by another")
    func pendingMilestoneStands() {
        let prompts = PromptsState()
        prompts.pendingReviewMilestone = .firstMemory
        prompts.notePartnerConnectedMilestone()
        #expect(prompts.pendingReviewMilestone == .firstMemory)
    }
}
