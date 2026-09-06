//
//  LiveActivityWordingTests.swift
//  TwofoldTests
//
//  A Live Activity is written from the point of view of the phone it is on. Both halves of a couple
//  start their own card for the same flight, so the same journey has to read correctly from either
//  side: "Sam is on the way to you" for the person waiting, "On the way to Erin" for the person
//  actually on the plane.
//
//  It used to be written only for the person waiting, so someone tracking their own flight was told
//  they were on the way to themselves.
//

import Testing
import Foundation
@testable import Twofold

struct LiveActivityWordingTests {

    private func attributes(traveler: String, partner: String, viewerIsTraveler: Bool) -> JourneyActivityAttributes {
        JourneyActivityAttributes(
            flightID: UUID(),
            travelerName: traveler,
            partnerName: partner,
            viewerIsTraveler: viewerIsTraveler,
            flightNumber: "UA60",
            airlineName: "United",
            originCode: "SFO",
            originCity: "San Francisco",
            destinationCode: "MEL",
            destinationCity: "Melbourne"
        )
    }

    /// The reported bug: a card started before this existed decodes with no perspective at all, and
    /// has to be replaced rather than left saying the wrong thing.
    @Test("a card with no perspective is replaced")
    func cardWithoutPerspectiveIsRestarted() throws {
        // Exactly what an already-running card looks like after this shipped: the old keys only.
        let legacy = """
        {"flightID":"\(UUID().uuidString)","travelerName":"Alex","flightNumber":"UA60",
         "originCode":"SFO","destinationCode":"MEL"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JourneyActivityAttributes.self, from: legacy)

        #expect(decoded.travelerName == "Alex", "an existing card must still decode, or it is orphaned on the Lock Screen")
        #expect(decoded.partnerName.isEmpty)
        #expect(
            LiveActivityManager.needsRestart(decoded, for: JourneyParticipants(travelerName: "Alex", partnerName: "Sam", viewerIsTraveler: true)),
            "a card with no perspective should be replaced"
        )
    }

    /// The negative control for the decoding above — without this, "it still decodes" could mean
    /// the decoder is ignoring the new fields entirely.
    @Test("a card written with a perspective keeps it")
    func perspectiveSurvivesARoundTrip() throws {
        let original = attributes(traveler: "Alex", partner: "Sam", viewerIsTraveler: true)
        let decoded = try JSONDecoder().decode(JourneyActivityAttributes.self, from: JSONEncoder().encode(original))
        #expect(decoded.viewerIsTraveler)
        #expect(decoded.partnerName == "Sam")
    }

    /// A card already saying the right thing must be left alone. Restarting one drops it off the
    /// Lock Screen and animates a new one in, which is not something to do on every refresh.
    @Test("a correct card is not restarted")
    func correctCardIsLeftAlone() {
        let current = attributes(traveler: "Alex", partner: "Sam", viewerIsTraveler: true)
        #expect(!LiveActivityManager.needsRestart(current, for: JourneyParticipants(travelerName: "Alex", partnerName: "Sam", viewerIsTraveler: true)))
    }

    /// And one whose travellers were edited after tracking began does need replacing — the flight
    /// was added as the partner's and then corrected to the user's own.
    @Test("a card is replaced when who is flying changes")
    func changedTravelerRestarts() {
        let started = attributes(traveler: "Sam", partner: "Alex", viewerIsTraveler: false)
        #expect(LiveActivityManager.needsRestart(started, for: JourneyParticipants(travelerName: "Alex", partnerName: "Sam", viewerIsTraveler: true)))
    }
}
