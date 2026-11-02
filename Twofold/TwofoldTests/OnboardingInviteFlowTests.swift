//
//  OnboardingInviteFlowTests.swift
//  TwofoldTests
//
//  The invitee's way through onboarding, and the screens either side of making an account.
//
//    ONB-3       A typed code went straight to "X invited you" without asking who X was, so the
//                headline stayed a grey placeholder, and a wrong code was only refused after an
//                account had been made for it.
//    NEW-1       A second invite link showed the first inviter's name until its own lookup came
//                back — and if the first lookup was the slower one, for good.
//    ONB-5       The sign-up screens stayed in the back stack once the account existed, one swipe
//                from signing up again; and swiping back to Home City redeemed the code twice.
//    ONB-8       A fast double tap on a question pushed the next one twice.
//    ONB-13      Killing the app part-way through the invitee flow resumed it as the inviter's.
//

import Foundation
import Testing
@testable import Twofold

@MainActor
struct OnboardingInviteFlowTests {

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - ONB-3: a typed code is checked before anything else happens

    @Test("a typed code nobody issued is refused on the code screen, before any account")
    func unknownTypedCodeIsRefused() async {
        let model = OnboardingModel()
        model.inviterLookup = { _ in nil }

        let message = await model.enterTypedCode("ABCD-EFGH")

        #expect(message != nil, "a code that does not exist was accepted")
        #expect(!model.path.contains(.joinInvite), "moved on to the invite screen for a code that does not exist")
    }

    @Test("a typed code resolves its inviter, so the headline can name them")
    func typedCodeResolvesInviter() async {
        let model = OnboardingModel()
        model.inviterLookup = { _ in BackendService.InviterInfo(name: "Max", avatarURL: nil) }

        let message = await model.enterTypedCode("abcd-efgh ")

        #expect(message == nil)
        #expect(model.path == [.joinInvite])
        #expect(model.hasResolvedInviterName, "JoinInviteView would sit on its placeholder forever")
        #expect(model.inviterName == "Max")
        #expect(model.inviteCode == "ABCD-EFGH")
        #expect(model.inviteOrigin == .code, "a typed code must still ask the inviter to approve")
    }

    @Test("a lookup that could not be made is not reported as a wrong code")
    func failedLookupSaysSo() async {
        struct Offline: Error {}
        let model = OnboardingModel()
        model.inviterLookup = { _ in throw Offline() }

        let message = await model.enterTypedCode("ABCD-EFGH")

        #expect(message != nil)
        #expect(message?.contains("couldn't find") == false, "an offline phone was told the code was wrong")
        #expect(!model.path.contains(.joinInvite))
    }

    // MARK: - NEW-1: a second link starts from nothing

    @Test("a new invite forgets the previous inviter at once")
    func newInviteClearsPreviousInviter() async {
        let model = OnboardingModel()
        let gate = Gate()
        model.inviterLookup = { _ in
            await gate.wait()
            return nil
        }
        model.inviterName = "Previous"
        model.hasResolvedInviterName = true

        model.resetForNewInvite(code: "NEWCODE1")

        #expect(model.inviterName == nil, "the last inviter's name is on the new invite")
        #expect(!model.hasResolvedInviterName, "the headline shows unredacted before its own lookup")
        gate.open()
    }

    @Test("the newest invite's inviter wins, whichever lookup lands last")
    func newestInviteWins() async {
        let model = OnboardingModel()
        let slow = Gate()
        model.inviterLookup = { code in
            if code == "FIRSTONE" {
                await slow.wait()
                return BackendService.InviterInfo(name: "Ann", avatarURL: nil)
            }
            return BackendService.InviterInfo(name: "Bea", avatarURL: nil)
        }

        model.resetForNewInvite(code: "FIRSTONE")
        await slow.untilSomeoneArrives()
        model.resetForNewInvite(code: "SECONDONE")
        await waitUntil { model.inviterName == "Bea" }
        slow.open()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.inviterName == "Bea", "the older link's lookup overwrote the newer one")
        #expect(model.inviteCode == "SECONDONE")
    }

    // MARK: - ONB-5: once the account exists, the sign-up screens are gone

    @Test("making the account clears the screens that made it")
    func accountCreationCollapsesTheStack() {
        let model = OnboardingModel()
        model.path = [.situation, .frequency, .twofoldPreview, .saveAccount]

        model.continueAfterAccountCreated(to: .invitePartner)

        #expect(model.path == [.invitePartner], "the sign-up form is still one swipe back")
    }

    @Test("a code already redeemed is not redeemed again on the way back through")
    func redeemsOnce() {
        let model = OnboardingModel()
        model.role = .invitee
        model.inviteCode = "ABCDEFGH"
        #expect(model.codeToRedeem == "ABCDEFGH")

        model.redeemedInviteCode = "ABCDEFGH"

        #expect(model.codeToRedeem == nil, "swiping back to Home City and pressing Continue redeems it twice")
    }

    // MARK: - ONB-8: a double tap pushes once

    @Test("pushing the step already on top does nothing")
    func doubleTapPushesOnce() {
        let model = OnboardingModel()
        model.push(.frequency)
        model.push(.frequency)
        #expect(model.path == [.frequency])

        model.push(.attribution)
        #expect(model.path == [.frequency, .attribution])
    }

    // MARK: - ONB-13: resuming an invitee resumes the invitee

    @Test("an invitee waiting on a reply resumes their own flow, not the inviter's")
    func resumesAwaitingInvitee() {
        let plan = OnboardingResume.plan(pendingRequestInviterName: "Max", savedInvite: nil)
        #expect(plan == .inviteeAwaitingReply(inviterName: "Max"))
    }

    @Test("an invitee killed before redeeming gets their code back")
    func resumesUnredeemedInvitee() {
        let saved = SavedInvite(code: "ABCDEFGH", origin: "link")
        #expect(OnboardingResume.plan(pendingRequestInviterName: nil, savedInvite: saved) == .inviteeToRedeem(saved))
    }

    @Test("a request already sent outranks a code kept from before it")
    func pendingRequestWins() {
        let saved = SavedInvite(code: "ABCDEFGH", origin: "code")
        #expect(OnboardingResume.plan(pendingRequestInviterName: "Max", savedInvite: saved) == .inviteeAwaitingReply(inviterName: "Max"))
    }

    @Test("everyone else resumes as the inviter")
    func resumesInviter() {
        #expect(OnboardingResume.plan(pendingRequestInviterName: nil, savedInvite: nil) == .inviter)
    }

    @Test("a saved code is per account and comes back as it went in")
    func savedInviteRoundTrip() {
        let me = UUID()
        let someoneElse = UUID()
        defer { OnboardingResume.clear(for: me) }
        let invite = SavedInvite(code: "ABCDEFGH", origin: "link")

        OnboardingResume.save(invite, for: me)

        #expect(OnboardingResume.savedInvite(for: me) == invite)
        #expect(OnboardingResume.savedInvite(for: me)?.inviteOrigin == .link)
        #expect(OnboardingResume.savedInvite(for: someoneElse) == nil)
        OnboardingResume.clear(for: me)
        #expect(OnboardingResume.savedInvite(for: me) == nil)
    }
}
