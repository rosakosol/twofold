//
//  FlightAllowanceTests.swift
//  TwofoldTests
//
//  The shared monthly flight limit, on the client side of it.
//
//  Two things are worth pinning here, and neither is arithmetic. The first is that a refusal
//  reaches a traveller as a sentence: `add-flight` answers a spent allowance with a machine
//  readable `code` beside a human `error`, and the two used to be one field — which meant the
//  limit refusal, the only one carrying a slug, would have put "monthly_flight_limit_reached" on
//  screen. The second is that an allowance the app could not read must not read as zero.
//

import Testing
import Foundation
@testable import Twofold

struct FlightAllowanceTests {

    /// The exact body `add-flight` returns when the couple is out of flights. Kept verbatim
    /// rather than built from constants, so this test fails if either side renames the code.
    private static let limitBody = Data("""
    {"error":"You've tracked 5 flights this month, which is everything your plan includes. Your allowance resets on the 1st.","code":"monthly_flight_limit_reached","used":5,"limit":5}
    """.utf8)

    /// And when the two of them aren't connected yet. Both `add-flight` and `resolve-flight`
    /// return this one.
    private static let notPairedBody = Data("""
    {"error":"Flight tracking starts once you and your partner are connected.","code":"not_paired"}
    """.utf8)

    @Test("a spent allowance is a typed refusal, not a generic failure")
    func limitIsRecognised() throws {
        let error = AeroFlightService.failure(status: 403, body: Self.limitBody)
        guard case .monthlyLimitReached(let used, let limit) = error else {
            Issue.record("got \(error) — the limit refusal was not recognised")
            return
        }
        #expect(used == 5)
        #expect(limit == 5)
    }

    /// The second half of the chain, asserted on the case rather than on a response body.
    ///
    /// Written this way after a negative control caught the first version being weaker than it
    /// looked: asserting on `failure(status:body:)`'s message passed even with the limit case
    /// deleted from the mapping, because the fallback shows the server's own `error` sentence,
    /// which reads perfectly well. That made it a test of the server's copy, not of the client's
    /// handling. Body-to-case is `limitIsRecognised` above; this is case-to-sentence, and
    /// together they cover what one assertion appeared to.
    @Test("the limit refusal reads as a sentence")
    func limitReadsAsASentence() {
        let message = AeroFlightError.monthlyLimitReached(used: 5, limit: 5).errorDescription ?? ""
        #expect(!message.contains("_"), "a machine-readable code reached the screen: \(message)")
        #expect(message.contains("5 flights"))
        #expect(message.contains("resets on the 1st"))
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

    /// Every other failure keeps the behaviour it had: show whatever the server said.
    @Test("an uncoded failure still shows the server's own message")
    func uncodedFailurePassesThrough() {
        let body = Data(#"{"error":"Flight not found"}"#.utf8)
        let error = AeroFlightService.failure(status: 404, body: body)
        guard case .requestFailed(let status, let message) = error else {
            Issue.record("got \(error)")
            return
        }
        #expect(status == 404)
        #expect(message == "Flight not found")
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
