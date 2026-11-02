//
//  OpenURLRouteTests.swift
//  TwofoldTests
//
//  Where a link opened into the app goes (ONB-1, ONB-2).
//
//  Two links were lost or misrouted. An invite or password-reset link that cold-launched the app
//  met the loading screen, and when loading finished RootView dropped it for anyone not already
//  in the main app — onboarding's own handler, the only one that knew what to do with it, was not
//  on screen when the link arrived. And somebody signed in but still onboarding who tapped an
//  invite was sent to "Create account" again, which makes a second account.
//

import Foundation
import Testing
@testable import Twofold

struct OpenURLRouteTests {

    private let invite = URL(string: "https://www.twofoldapp.com.au/invite/ABCDEFGH")!
    private let recovery = URL(string: "https://www.twofoldapp.com.au/auth/reset-password?code=x")!
    private let widget = URL(string: "twofold://memories")!

    @Test("a link that arrives while the session loads is kept for later")
    func waitsForSession() {
        #expect(OpenURLRoute.route(for: invite, isLoadingSession: true, hasCouple: false, isSignedIn: false) == .wait)
        #expect(OpenURLRoute.route(for: widget, isLoadingSession: true, hasCouple: true, isSignedIn: true) == .wait)
    }

    /// The cold launch: loading finished, nobody signed in. This used to come back `.ignore`.
    @Test("signed out, an invite starts onboarding's invitee flow")
    func signedOutInviteStartsInviteeFlow() {
        #expect(OpenURLRoute.route(for: invite, isLoadingSession: false, hasCouple: false, isSignedIn: false) == .startInvite(code: "ABCDEFGH"))
    }

    @Test("signed out, a password-reset link reaches onboarding")
    func signedOutRecoveryLink() {
        #expect(OpenURLRoute.route(for: recovery, isLoadingSession: false, hasCouple: false, isSignedIn: false) == .passwordRecovery(recovery))
    }

    /// ONB-2. An account already exists, so the redeem sheet — never the sign-up screens.
    @Test("signed in but still onboarding, an invite opens the redeem sheet")
    func midOnboardingInviteRedeems() {
        #expect(OpenURLRoute.route(for: invite, isLoadingSession: false, hasCouple: false, isSignedIn: true) == .redeemInvite(code: "ABCDEFGH"))
    }

    @Test("in the app, an invite opens the redeem sheet")
    func pairedInviteRedeems() {
        #expect(OpenURLRoute.route(for: invite, isLoadingSession: false, hasCouple: true, isSignedIn: true) == .redeemInvite(code: "ABCDEFGH"))
    }

    @Test("widget links only mean something in the app")
    func widgetLinks() {
        #expect(OpenURLRoute.route(for: widget, isLoadingSession: false, hasCouple: true, isSignedIn: true) == .widget(.memories))
        #expect(OpenURLRoute.route(for: widget, isLoadingSession: false, hasCouple: false, isSignedIn: false) == .ignore)
    }
}
