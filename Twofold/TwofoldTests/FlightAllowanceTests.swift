//
//  FlightAllowanceTests.swift
//  TwofoldTests
//
//  Typed refusals from the flight endpoints, on the client side of them.
//
//  Two things are worth pinning here, and neither is arithmetic. The first is that a refusal
//  reaches a traveller as a sentence: the edge functions answer with a machine-readable `code`
//  beside a human `error`, and the two used to be one field — which meant any refusal carrying a
//  slug would have put it on screen. The second is that an allowance the app could not read must
//  not read as zero.
//
//  The subject was the monthly limit until that refusal stopped existing: the allowance moved onto
//  live tracking, so `add-flight` saves an over-cap flight untracked rather than refusing it. The
//  live refusal carrying a code is now `premium_required`, from `flight-delay-stats`, and the same
//  two properties are asserted about it.
//
//  Since then the rule has widened: no sentence an edge function writes reaches a traveller at all.
//  A plan refusal (`subscription_required` from `add-flight` and `resolve-flight`, and
//  `premium_required`) opens the paywall, and every other failure reads in the app's own words.
//

import Testing
import Foundation
@testable import Twofold

struct FlightAllowanceTests {

    /// The exact body `flight-delay-stats` returns to a couple on Plus. Kept verbatim rather than
    /// built from constants, so this test fails if either side renames the code.
    private static let premiumBody = Data("""
    {"error":"Delay analysis is included with Twofold Premium.","code":"premium_required"}
    """.utf8)

    /// And when the two of them aren't connected yet. Both `add-flight` and `resolve-flight`
    /// return this one.
    private static let notPairedBody = Data("""
    {"error":"Flight tracking starts once you and your partner are connected.","code":"not_paired"}
    """.utf8)

    @Test("a Premium-only endpoint refuses as a typed case, not a generic failure")
    func premiumRefusalIsRecognised() throws {
        let error = AeroFlightService.failure(status: 403, body: Self.premiumBody)
        guard case .premiumRequired = error else {
            Issue.record("got \(error) — the premium refusal was not recognised")
            return
        }
    }

    /// The second half of the chain, asserted on the case rather than on a response body.
    ///
    /// Written this way after a negative control caught the first version being weaker than it
    /// looked: asserting on `failure(status:body:)`'s message passed even with the case deleted
    /// from the mapping, because the fallback shows the server's own `error` sentence, which reads
    /// perfectly well. That made it a test of the server's copy, not of the client's handling.
    /// Body-to-case is the test above; this is case-to-sentence, and together they cover what one
    /// assertion appeared to.
    @Test("the premium refusal reads as a sentence")
    func premiumReadsAsASentence() {
        let message = AeroFlightError.premiumRequired.errorDescription ?? ""
        #expect(!message.contains("_"), "a machine-readable code reached the screen: \(message)")
        #expect(message.contains("Premium"))
    }

    @Test("an unpaired refusal explains the pairing, not the couples table")
    func notPairedReadsAsASentence() {
        let error = AeroFlightService.failure(status: 403, body: Self.notPairedBody)
        guard case .notPaired = error else {
            Issue.record("got \(error)")
            return
        }
        let message = error.errorDescription ?? ""
        #expect(!message.lowercased().contains("couple id"))
        #expect(message.contains("partner"))
    }

    /// The exact refusal `add-flight` and `resolve-flight` both return to a couple with no active
    /// subscription. Verbatim, for the same reason as the bodies above.
    private static let subscriptionBody = Data("""
    {"error":"Tracking a new flight needs an active subscription. Everything you've already saved stays where it is.","code":"subscription_required"}
    """.utf8)

    /// The free couple's refusal from flight search and add flight. It used to fall through to
    /// `requestFailed` and put the server's sentence on screen, where the way on is the paywall.
    @Test("a no-subscription refusal is its own case, not the server's sentence")
    func subscriptionRefusalIsRecognised() {
        let error = AeroFlightService.failure(status: 403, body: Self.subscriptionBody)
        if case .requestFailed = error {
            Issue.record("got \(error) — the subscription refusal fell through to the server's own text")
        }
        #expect(error.errorDescription != "Tracking a new flight needs an active subscription. Everything you've already saved stays where it is.")
    }

    /// What the search and confirm screens branch on: a plan to sell means the paywall, on that
    /// plan, and nothing else does.
    @Test("the plan refusals open the paywall on the plan they need, and nothing else does")
    func paywallTierPerRefusal() {
        #expect(AeroFlightService.failure(status: 403, body: Self.subscriptionBody).paywallTier == .plus)
        #expect(AeroFlightService.failure(status: 403, body: Self.premiumBody).paywallTier == .premium)
        #expect(AeroFlightService.failure(status: 403, body: Self.notPairedBody).paywallTier == nil)
        #expect(AeroFlightService.failure(status: 404, body: Data(#"{"error":"Flight not found"}"#.utf8)).paywallTier == nil)
        #expect(AeroFlightError.notAuthenticated.paywallTier == nil)
        #expect(AeroFlightError.decodingFailed.paywallTier == nil)
    }

    /// A 401 from the function itself, as opposed to no session on the device. Both mean the same
    /// thing to the person, and "Not authenticated" is not how the app says it.
    @Test("a 401 body reads as signed out")
    func unauthorisedIsSignedOut() {
        let error = AeroFlightService.failure(status: 401, body: Data(#"{"error":"Not authenticated"}"#.utf8))
        guard case .notAuthenticated = error else {
            Issue.record("got \(error)")
            return
        }
    }

    /// Whatever a screen is handed, the sentence is the app's. Errors that are not flight errors
    /// at all fall back to the screen's own words rather than their `localizedDescription`.
    @Test("a non-flight error falls back to the screen's own words")
    func messageFallsBack() {
        struct Other: LocalizedError { var errorDescription: String? { "URLSession said something" } }
        #expect(AeroFlightError.message(for: Other(), fallback: "Try again.") == "Try again.")
        #expect(AeroFlightError.message(for: AeroFlightError.notPaired, fallback: "Try again.").contains("partner"))
    }

    /// Nothing the edge functions write reaches a traveller. Their sentences are written for
    /// whoever reads the logs — "'date' must be YYYY-MM-DD", "Flight lookup failed: AeroAPI 500"
    /// — and the app has its own words for every status it can get.
    @Test("an uncoded failure shows the app's words, never the server's", arguments: [
        (400, #"{"error":"'date' must be YYYY-MM-DD"}"#, "'date' must be YYYY-MM-DD"),
        (404, #"{"error":"Flight not found"}"#, "Flight not found"),
        (429, #"{"error":"You've done that a few too many times just now — please try again a bit later."}"#,
         "You've done that a few too many times just now — please try again a bit later."),
        (500, #"{"error":"Failed to save flight"}"#, "Failed to save flight"),
        (502, #"{"error":"Flight lookup failed: AeroAPI 500 Internal Server Error"}"#, "Flight lookup failed: AeroAPI 500 Internal Server Error"),
        (503, #"{"error":"Couldn't check your subscription. Please try again."}"#, "Couldn't check your subscription. Please try again."),
    ])
    func uncodedFailureUsesAppCopy(status: Int, body: String, serverSentence: String) {
        let error = AeroFlightService.failure(status: status, body: Data(body.utf8))
        let message = error.errorDescription ?? ""
        #expect(!message.isEmpty)
        #expect(message != serverSentence, "the server's own sentence reached the screen for \(status)")
        #expect(!message.contains("AeroAPI"), "a supplier's name reached the screen: \(message)")
    }

    /// A 502 with an HTML body, or an empty one. Decoding fails, and that must not be mistaken
    /// for one of the coded cases.
    @Test("an undecodable body is a plain failure")
    func undecodableBodyIsPlain() {
        let error = AeroFlightService.failure(status: 502, body: Data("<html>bad gateway</html>".utf8))
        guard case .requestFailed(let status, let message) = error else {
            Issue.record("got \(error)")
            return
        }
        #expect(status == 502)
        #expect(message == nil)
    }

    // MARK: - What the confirm screen shows

    /// `used` above `limit` is legitimate, not a bug to guard against with an assertion: two
    /// simultaneous adds can both pass the server's pre-check. It must not render as "-1 left".
    @Test("remaining never goes negative")
    func remainingNeverGoesNegative() throws {
        let overspent = try JSONDecoder().decode(
            BackendService.FlightAllowance.self,
            from: Data(#"{"tier":"plus","limit":5,"used":6}"#.utf8)
        )
        #expect(overspent.remaining == 0)

        let fresh = try JSONDecoder().decode(
            BackendService.FlightAllowance.self,
            from: Data(#"{"tier":"premium","limit":20,"used":3}"#.utf8)
        )
        #expect(fresh.remaining == 17)
    }

    /// The tier is nullable — a couple with no subscription row resolves to no tier at all, and
    /// the allowance still has to decode. This is the shape that would otherwise crash the
    /// confirm screen's lookup for exactly the free-tier users the limit applies hardest to.
    @Test("an allowance with no tier still decodes")
    func nullTierDecodes() throws {
        let allowance = try JSONDecoder().decode(
            BackendService.FlightAllowance.self,
            from: Data(#"{"tier":null,"limit":5,"used":0}"#.utf8)
        )
        #expect(allowance.tier == nil)
        #expect(allowance.remaining == 5)
    }
}

//
//  Which refusal it was, for the one control that shows it.
//
//  `enable_flight_tracking` has always answered `{enabled: false, reason: ...}` and the client has
//  always thrown the reason away and shown the allowance sentence — "you've used all your
//  live-tracked flights this month, your allowance resets on the 1st." That was correct by accident
//  while `limit_reached` was the only refusal it could give.
//
//  20261110001800 added a second one. The subscription gate of 20261028000000 never reached flights
//  — no policy grants clients INSERT on `public.flights`, so RLS could not express it — which left
//  the one kind of content that costs real money as the only kind a lapsed couple could still add.
//  Closing that made the hardcoded sentence a lie: it tells somebody whose subscription has lapsed
//  to wait for a reset that will not help them.
//
//  Bodies are the exact jsonb the function builds, so a reason renamed on either side fails here.
//
struct FlightTrackingRefusalTests {

    private func result(_ json: String) throws -> BackendService.FlightTrackingResult {
        try JSONDecoder().decode(BackendService.FlightTrackingResult.self, from: Data(json.utf8))
    }

    @Test("the lapsed-subscription refusal does not read as a spent allowance")
    func subscriptionRefusalIsItsOwnSentence() throws {
        let refused = try result(#"{"reason": "subscription_required", "enabled": false}"#)
        #expect(!refused.enabled)
        let message = BackendService.FlightTrackingRefusal.message(for: refused.reason)
        #expect(message.contains("subscription"))
        #expect(!message.contains("1st"), "a lapsed couple was told to wait for a reset: \(message)")
        #expect(!message.contains("_"), "a machine-readable code reached the screen: \(message)")
    }

    /// The card answers this one with the paywall, as search and add do; nothing else does.
    @Test("only the lapsed-subscription refusal opens the paywall")
    func onlySubscriptionRefusalOpensPaywall() {
        #expect(BackendService.FlightTrackingRefusal.opensPaywall("subscription_required"))
        for reason in ["limit_reached", "flight_over", "something_new", ""] {
            #expect(!BackendService.FlightTrackingRefusal.opensPaywall(reason), "\(reason) opened the paywall")
        }
        #expect(!BackendService.FlightTrackingRefusal.opensPaywall(nil))
    }

    @Test("the allowance refusal still names the reset")
    func allowanceRefusalUnchanged() throws {
        let refused = try result(#"{"used": 5, "limit": 5, "reason": "limit_reached", "enabled": false}"#)
        #expect(!refused.enabled)
        let message = BackendService.FlightTrackingRefusal.message(for: refused.reason)
        #expect(message.contains("1st"))
        #expect(!message.contains("subscription"))
    }

    /// A flight that arrived between the card rendering and the button being tapped. Rare, and it
    /// used to read as a spent allowance too.
    @Test("an arrived flight says so rather than blaming the allowance")
    func arrivedFlightHasItsOwnSentence() throws {
        let refused = try result(#"{"enabled": false, "reason": "flight_over"}"#)
        let message = BackendService.FlightTrackingRefusal.message(for: refused.reason)
        #expect(message.contains("arrived"))
        #expect(!message.contains("1st"))
    }

    /// The fallback has to be a sentence, not an empty string: a server that grows a fourth reason
    /// must not leave the card showing nothing where an explanation should be.
    @Test("a reason this build has never heard of still explains itself")
    func unknownReasonFallsBack() throws {
        for reason in ["something_new", ""] {
            let message = BackendService.FlightTrackingRefusal.message(for: reason)
            #expect(!message.isEmpty)
            #expect(!message.contains("_"), "a machine-readable code reached the screen: \(message)")
        }
        #expect(!BackendService.FlightTrackingRefusal.message(for: nil).isEmpty)
    }

    /// The success shapes both have to decode, or a granted slot reads as a thrown error and the
    /// person is told to try again after it already worked.
    @Test("both success bodies decode, with no reason attached")
    func successDecodes() throws {
        let spent = try result(#"{"used": 2, "limit": 5, "enabled": true}"#)
        #expect(spent.enabled)
        #expect(spent.reason == nil)

        let already = try result(#"{"enabled": true, "already_tracking": true}"#)
        #expect(already.enabled)
        #expect(already.reason == nil)
    }
}
