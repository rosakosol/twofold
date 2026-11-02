//
//  OnboardingScreenDecisionTests.swift
//  TwofoldTests
//
//  Decisions individual screens make, each pulled out of its view to be tested here.
//
//    ONB-6   Signing back in with Apple or Google to an account that onboarding had already made
//            was told "we've started a new account", and pointed at a Settings it cannot reach.
//    ONB-7   Closing the Apple or Google sheet showed a red error.
//    ONB-9   A link's code, cleared and replaced by a typed one, still redeemed as a link — and so
//            connected without the other inviter's approval.
//    ONB-10  Accept on the review screen skipped the "bring your history back" question when
//            tapped before the archive lookup had answered.
//    ONB-11  Partner setup celebrated the anniversary on any Save made on that day of the year,
//            including for couples with no anniversary at all (it defaults to today).
//    ONB-19  The first-memory step reopened its form every time it appeared, so going back from
//            the next screen opened it again and pushed the next screen again.
//

import AuthenticationServices
import Foundation
import Testing
@testable import Twofold

struct OnboardingScreenDecisionTests {

    // MARK: - ONB-6

    @Test("signing back in to an account onboarding already made is not called a new account")
    func returningProviderAccountIsNotNew() {
        #expect(!SignInView.shouldExplainNewProviderAccount(viaProvider: true, hasSavedOnboardingProgress: true))
        #expect(SignInView.shouldExplainNewProviderAccount(viaProvider: true, hasSavedOnboardingProgress: false))
        #expect(!SignInView.shouldExplainNewProviderAccount(viaProvider: false, hasSavedOnboardingProgress: false))
    }

    /// Settings is not reachable from onboarding. The way out of a session there is Back.
    @Test("the new-account message points somewhere the person can actually go")
    func newAccountMessageNamesAReachableWayOut() {
        #expect(!SignInView.newProviderAccountMessage.contains("Settings"))
        #expect(SignInView.newProviderAccountMessage.contains("Back"))
    }

    // MARK: - ONB-7

    @Test("closing the Apple sheet is a cancellation, not an error")
    func appleCancel() {
        #expect(AppleGoogleSignInButtons.isUserCancellation(ASAuthorizationError(.canceled)))
        #expect(!AppleGoogleSignInButtons.isUserCancellation(ASAuthorizationError(.failed)))
    }

    /// `kGIDSignInErrorDomain` and `GIDSignInErrorCode.canceled`, written out so a change in the
    /// SDK shows up here.
    @Test("closing the Google sheet is a cancellation, not an error")
    func googleCancel() {
        #expect(AppleGoogleSignInButtons.isUserCancellation(NSError(domain: "com.google.GIDSignIn", code: -5)))
        #expect(!AppleGoogleSignInButtons.isUserCancellation(NSError(domain: "com.google.GIDSignIn", code: -1)))
        #expect(!AppleGoogleSignInButtons.isUserCancellation(BackendError.notAuthenticated))
    }

    // MARK: - ONB-9

    @Test("the link's own code redeems as a link")
    func linkCodeIsLink() {
        #expect(RedeemPartnerCodeView.origin(forCode: "ABCD-EFGH", prefilledCode: "ABCD-EFGH") == .link)
        #expect(RedeemPartnerCodeView.origin(forCode: "ABCD-EFGH", prefilledCode: "abcdefgh") == .link, "formatting is not a different code")
    }

    @Test("a different code typed over a link's redeems as typed")
    func editedCodeIsTyped() {
        #expect(RedeemPartnerCodeView.origin(forCode: "WXYZ-QRST", prefilledCode: "ABCD-EFGH") == .code)
    }

    // MARK: - ONB-10

    @Test("Accept waits until it is known whether there is history to bring back")
    func acceptWaitsForArchiveLookup() {
        #expect(ConnectionRequestReviewView.acceptAction(hasCheckedForArchive: false, hasRestorableArchive: false) == .wait)
        #expect(ConnectionRequestReviewView.acceptAction(hasCheckedForArchive: true, hasRestorableArchive: true) == .askAboutArchive)
        #expect(ConnectionRequestReviewView.acceptAction(hasCheckedForArchive: true, hasRestorableArchive: false) == .accept)
    }

    // MARK: - ONB-11

    @Test("a Save that left the anniversary alone does not celebrate it")
    func untouchedAnniversaryIsNotCelebrated() {
        let today = Date()
        #expect(!PartnerSetupView.shouldCelebrate(original: today, picked: today, now: today))
    }

    @Test("setting the anniversary to today's date celebrates it")
    func changedToTodayIsCelebrated() {
        let calendar = Calendar.current
        let today = Date()
        let yearsAgo = calendar.date(byAdding: .year, value: -3, to: today)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: yearsAgo)!
        #expect(PartnerSetupView.shouldCelebrate(original: lastMonth, picked: yearsAgo, now: today))
        #expect(!PartnerSetupView.shouldCelebrate(original: yearsAgo, picked: lastMonth, now: today))
    }

    // MARK: - ONB-19

    @Test("the memory form opens once, and coming back to it steps back past it")
    func firstMemoryFormOpensOnce() {
        #expect(FirstMemoryView.appearAction(hasPresentedForm: false) == .presentForm)
        #expect(FirstMemoryView.appearAction(hasPresentedForm: true) == .stepBack)
    }
}
