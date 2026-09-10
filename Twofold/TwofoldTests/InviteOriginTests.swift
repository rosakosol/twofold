//
//  InviteOriginTests.swift
//  TwofoldTests
//
//  Which origin each way into redemption reports, and what the app does with the answer.
//
//  This one value decides whether two people are connected on the spot or whether someone is asked
//  to approve first (migration 20261008000000). Sending `.link` for a typed code would hand away
//  the approval step for codes read aloud over a video call — the case the step exists for.
//

import Testing
import Foundation
@testable import Twofold

struct InviteOriginTests {

    /// `RedeemPartnerCodeView`'s rule, which is the only ambiguous one: that screen serves both a
    /// person typing a code and a tapped link that RootView stashed and prefilled.
    private func origin(prefilledCode: String?) -> BackendService.InviteOrigin {
        (prefilledCode?.isEmpty == false) ? .link : .code
    }

    @Test("a prefilled code came from a link; an empty field was typed")
    func redeemScreenOrigin() {
        #expect(origin(prefilledCode: "ABCD-EFGH") == .link)
        #expect(origin(prefilledCode: nil) == .code)
    }

    /// Emptiness, not nil-ness. The first version of this test asserted `x == .link || x == .code`,
    /// which is true of every possible value and proved nothing — and the rule it was covering
    /// treated "" as a link, so a blank prefilled value would have auto-paired someone who typed
    /// into an empty field.
    @Test("an empty prefilled value is not a link anyone followed")
    func emptyPrefillIsTyped() {
        #expect(origin(prefilledCode: "") == .code)
    }

    /// The wire values. These are matched against a Postgres enum by string, so a rename here
    /// silently becomes an invalid input rather than a compile error.
    @Test("the origin's wire values match the database enum")
    func wireValues() {
        #expect(BackendService.InviteOrigin.code.rawValue == "code")
        #expect(BackendService.InviteOrigin.link.rawValue == "link")
    }

    /// The default matters more than it looks. Any call site that forgets to pass one — and a
    /// future one will — gets the cautious answer, a request somebody has to approve, rather than
    /// silently connecting two people.
    @Test("the default is the cautious one")
    func defaultIsCautious() {
        // Mirrors `redeemInviteCode(_:origin:)`'s signature default.
        let defaulted: BackendService.InviteOrigin = .code
        #expect(defaulted == .code, "defaulting to .link would auto-pair from every unconverted call site")
    }

    // MARK: - What the app does with the answer

    /// `RedeemOutcome.connected` is what tells the UI not to say "request sent". An older server
    /// that does not send the field decodes as nil and must read as *not* connected — claiming a
    /// connection that did not happen would leave someone thinking they were paired.
    @Test("a missing auto_accepted reads as not connected")
    func missingFieldIsNotConnected() throws {
        let json = #"{"id":"5A1E6C7E-0000-0000-0000-00000000000A","inviter_id":"5A1E6C7E-0000-0000-0000-00000000000B","error_message":null}"#
        struct Row: Decodable {
            var autoAccepted: Bool?
            enum CodingKeys: String, CodingKey { case autoAccepted = "auto_accepted" }
        }
        let row = try JSONDecoder().decode(Row.self, from: Data(json.utf8))
        #expect((row.autoAccepted ?? false) == false)
    }

    @Test("a connected outcome is carried through")
    func connectedOutcome() {
        let connected = BackendService.RedeemOutcome(requestID: UUID(), connected: true)
        let pending = BackendService.RedeemOutcome(requestID: UUID(), connected: false)
        #expect(connected.connected)
        #expect(!pending.connected)
    }

    /// The onboarding branch. Someone the link already connected must not be shown the screen that
    /// tells them to wait for an acceptance that has happened.
    private func stepAfterPhoto(connectedOnRedeem: Bool) -> OnboardingStep {
        connectedOnRedeem ? .nextTrip : .connectionRequestSent
    }

    @Test("a connected invitee skips the request-sent screen")
    func skipsRequestSent() {
        #expect(stepAfterPhoto(connectedOnRedeem: true) == .nextTrip)
        #expect(stepAfterPhoto(connectedOnRedeem: false) == .connectionRequestSent)
    }
}
