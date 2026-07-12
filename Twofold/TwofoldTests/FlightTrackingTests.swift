//
//  FlightTrackingTests.swift
//  TwofoldTests
//
//  Unit tests for the pure, client-side flight-tracking logic: status semantics, countdown/
//  progress/timeline derivation, notification-preference mapping, and decoding the
//  resolve-flight Edge Function's JSON response. The AeroAPI response -> DB row mapping and
//  RLS/authorization themselves live server-side (Deno) and aren't testable here — see
//  supabase/functions/_shared/flight-sync.ts, which the flight-tracking summary documents as
//  verified manually against a real in-progress flight post-deploy.
//

import Foundation
import Testing
@testable import Twofold

struct FlightTrackingTests {

    private let melbourne = FlightAirport(iata: "MEL", icao: "YMML", name: "Melbourne Airport", city: "Melbourne", timezone: "Australia/Melbourne", latitude: -37.8136, longitude: 144.9631)
    private let singapore = FlightAirport(iata: "SIN", icao: "WSSS", name: "Changi Airport", city: "Singapore", timezone: "Asia/Singapore", latitude: 1.3521, longitude: 103.8198)

    private func makeFlight(
        status: FlightStatus = .scheduled,
        scheduledOut: Date? = nil,
        scheduledIn: Date? = nil,
        actualOut: Date? = nil,
        actualOff: Date? = nil,
        actualOn: Date? = nil,
        actualIn: Date? = nil,
        terminalOrigin: String? = nil,
        gateOrigin: String? = nil,
        baggageClaim: String? = nil,
        departureDelaySeconds: Int? = nil
    ) -> Flight {
        Flight(
            flightNumberIATA: "QF35", airlineCode: "QF",
            origin: singapore, destination: melbourne,
            scheduledOut: scheduledOut, scheduledIn: scheduledIn,
            actualOut: actualOut, actualOff: actualOff, actualOn: actualOn, actualIn: actualIn,
            departureDelaySeconds: departureDelaySeconds,
            terminalOrigin: terminalOrigin, gateOrigin: gateOrigin, baggageClaim: baggageClaim,
            status: status
        )
    }

    // MARK: - FlightStatus semantics (exhaustive over all cases)

    @Test func everyStatusHasNonEmptyDisplayLabelAndIcon() {
        for status in FlightStatus.allCases {
            #expect(!status.displayLabel.isEmpty)
            #expect(!status.icon.isEmpty)
            #expect(!status.emotionalHeadline.isEmpty)
        }
    }

    @Test func delayedCancelledDivertedAreNotSemanticallyGreen() {
        for status: FlightStatus in [.delayed, .cancelled, .diverted] {
            #expect(status.semanticColor == Theme.heartRed)
        }
    }

    @Test func arrivedAndLandedAreSemanticallyGreen() {
        #expect(FlightStatus.arrived.semanticColor == Theme.leafGreen)
        #expect(FlightStatus.landed.semanticColor == Theme.leafGreen)
    }

    @Test func isActivelyTrackedCoversOnlyInProgressStates() {
        let activeStates: Set<FlightStatus> = [.boarding, .departed, .inAir, .landingSoon]
        for status in FlightStatus.allCases {
            #expect(status.isActivelyTracked == activeStates.contains(status))
        }
    }

    // MARK: - Trip.isActive derives from Flight.status, not just departure date

    @Test func tripIsActiveWhenFlightIsActivelyTracked() {
        let flight = makeFlight(status: .inAir)
        var trip = Trip(travelerID: UUID(), origin: Place(city: "Singapore", country: "Singapore", latitude: 1.35, longitude: 103.8), destination: Place(city: "Melbourne", country: "Australia", latitude: -37.8, longitude: 144.9), departureDate: .now.addingTimeInterval(-3600), arrivalDate: .now.addingTimeInterval(3600), category: .seeingEachOther, distanceKm: 6000)
        trip.flight = flight
        #expect(trip.isActive)
    }

    @Test func tripIsNotActiveWhenFlightIsOnlyScheduled() {
        var trip = Trip(travelerID: UUID(), origin: Place(city: "Singapore", country: "Singapore", latitude: 1.35, longitude: 103.8), destination: Place(city: "Melbourne", country: "Australia", latitude: -37.8, longitude: 144.9), departureDate: .now.addingTimeInterval(86_400), arrivalDate: .now.addingTimeInterval(90_000), category: .seeingEachOther, distanceKm: 6000)
        trip.flight = makeFlight(status: .scheduled, scheduledOut: .now.addingTimeInterval(86_400))
        #expect(!trip.isActive)
    }

    @Test func tripWithNoFlightIsNeverActive() {
        let trip = Trip(travelerID: UUID(), origin: Place(city: "Singapore", country: "Singapore", latitude: 1.35, longitude: 103.8), destination: Place(city: "Melbourne", country: "Australia", latitude: -37.8, longitude: 144.9), departureDate: .now.addingTimeInterval(-3600), arrivalDate: .now.addingTimeInterval(3600), category: .seeingEachOther, distanceKm: 6000)
        #expect(!trip.isActive)
    }

    // MARK: - Countdown summary

    @Test func countdownSummaryForScheduledFutureDeparture() {
        let flight = makeFlight(status: .scheduled, scheduledOut: .now.addingTimeInterval(3600 * 2 + 60))
        #expect(flight.countdownSummary.hasPrefix("Departs in"))
    }

    @Test func countdownSummaryForInAirShowsArrival() {
        let flight = makeFlight(status: .inAir, scheduledOut: .now.addingTimeInterval(-3600), scheduledIn: .now.addingTimeInterval(3600), actualOut: .now.addingTimeInterval(-3600), actualOff: .now.addingTimeInterval(-3500))
        #expect(flight.countdownSummary.hasPrefix("Arrives in"))
    }

    @Test func countdownSummaryForArrivedShowsElapsed() {
        let arrival = Date.now.addingTimeInterval(-900)
        let flight = makeFlight(status: .arrived, scheduledOut: arrival.addingTimeInterval(-3600), scheduledIn: arrival, actualIn: arrival)
        #expect(flight.countdownSummary.hasPrefix("Arrived"))
        #expect(flight.countdownSummary.hasSuffix("ago"))
    }

    @Test func countdownSummaryForCancelledIsUnambiguous() {
        let flight = makeFlight(status: .cancelled)
        #expect(flight.countdownSummary == "Cancelled")
    }

    // MARK: - Progress

    @Test func progressIsZeroBeforeDeparture() {
        let flight = makeFlight(status: .scheduled, scheduledOut: .now.addingTimeInterval(3600), scheduledIn: .now.addingTimeInterval(7200))
        #expect(flight.progress == 0)
    }

    @Test func progressIsFullAfterArrival() {
        let flight = makeFlight(status: .arrived, scheduledOut: .now.addingTimeInterval(-7200), scheduledIn: .now.addingTimeInterval(-3600), actualIn: .now.addingTimeInterval(-3600))
        #expect(flight.progress == 1)
    }

    @Test func progressIsBetweenZeroAndOneMidFlight() {
        let departure = Date.now.addingTimeInterval(-3600)
        let arrival = Date.now.addingTimeInterval(3600)
        let flight = makeFlight(status: .inAir, scheduledOut: departure, scheduledIn: arrival, actualOut: departure, actualOff: departure)
        #expect(flight.progress > 0 && flight.progress < 1)
    }

    // MARK: - Timeline derivation

    @Test func timelineForPurelyScheduledFlightHasIncompleteDepartedEvent() {
        let flight = makeFlight(status: .scheduled, scheduledOut: .now.addingTimeInterval(3600))
        let departedEvent = flight.timeline.first { $0.kind == .departed }
        #expect(departedEvent != nil)
        #expect(departedEvent?.isComplete == false)
    }

    @Test func timelineForArrivedFlightMarksArrivedComplete() {
        let departure = Date.now.addingTimeInterval(-7200)
        let arrival = Date.now.addingTimeInterval(-60)
        let flight = makeFlight(status: .arrived, scheduledOut: departure, scheduledIn: arrival, actualOut: departure, actualOff: departure, actualOn: arrival, actualIn: arrival)
        let arrivedEvent = flight.timeline.first { $0.kind == .arrived }
        #expect(arrivedEvent?.isComplete == true)
    }

    // MARK: - FlightStatusEventType human copy

    @Test func gateChangeEventInterpolatesNewValue() {
        #expect(FlightStatusEventType.gateChange.label(newValue: "7") == "Gate changed to 7")
    }

    @Test func genericLabelUsedWhenNoNewValueProvided() {
        #expect(FlightStatusEventType.departed.label(newValue: nil) == "Departed")
    }

    @Test func delayEventInterpolatesFormattedDuration() {
        #expect(FlightStatusEventType.delay.label(newValue: "45 min") == "Flight delayed by 45 min")
    }

    // MARK: - Notification preference -> event type mapping

    @Test func gateTerminalPreferenceGatesGateAndTerminalEvents() {
        var prefs = FlightNotificationPreferences(flightID: UUID(), profileID: UUID())
        prefs.gateTerminalChanges = false
        #expect(!prefs.allows(.gateChange))
        #expect(!prefs.allows(.terminalChange))
        #expect(prefs.allows(.departed))
    }

    @Test func delayOrCancellationPreferenceCoversDelayCancelledDiverted() {
        var prefs = FlightNotificationPreferences(flightID: UUID(), profileID: UUID())
        prefs.delayOrCancellation = false
        #expect(!prefs.allows(.delay))
        #expect(!prefs.allows(.cancelled))
        #expect(!prefs.allows(.diverted))
    }

    @Test func baggageClaimPreferenceIsIndependentOfLanding() {
        var prefs = FlightNotificationPreferences(flightID: UUID(), profileID: UUID())
        prefs.baggageClaimUpdate = false
        prefs.landing = true
        #expect(!prefs.allows(.baggageClaim))
        #expect(prefs.allows(.landed))
    }

    // MARK: - Decoding resolve-flight's JSON response shape

    @Test func decodesAeroFlightCandidateFromResolveFlightJSONShape() throws {
        let json = """
        {
          "faFlightId": "QFA35-1234567890-airline-0123",
          "identIata": "QF35",
          "identIcao": "QFA35",
          "operatorName": null,
          "operatorIata": "QF",
          "flightNumberIata": "QF35",
          "aircraftType": "B789",
          "origin": { "iata": "SIN", "icao": "WSSS", "name": "Changi Airport", "city": "Singapore", "timezone": "Asia/Singapore" },
          "destination": { "iata": "MEL", "icao": "YMML", "name": "Melbourne Airport", "city": "Melbourne", "timezone": "Australia/Melbourne" },
          "scheduledOut": "2026-09-14T10:20:00Z",
          "scheduledIn": "2026-09-14T22:05:00Z",
          "status": "scheduled",
          "cancelled": false,
          "diverted": false,
          "isCodeshare": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let candidate = try decoder.decode(AeroFlightCandidate.self, from: json)

        #expect(candidate.faFlightId == "QFA35-1234567890-airline-0123")
        #expect(candidate.origin?.city == "Singapore")
        #expect(candidate.destination?.iata == "MEL")
        #expect(candidate.displayFlightNumber == "QF35")
        #expect(candidate.status == "scheduled")
        #expect(candidate.cancelled == false)
    }

    @Test func decodesAeroFlightCandidateWithNullOriginGracefully() throws {
        // AeroAPI occasionally omits origin/destination entirely — resolve-flight passes that
        // through as JSON null rather than fabricating placeholder airport data.
        let json = """
        {
          "faFlightId": "QFA35-1234567890-airline-0123",
          "identIata": "QF35",
          "identIcao": null,
          "operatorName": null,
          "operatorIata": "QF",
          "flightNumberIata": "QF35",
          "aircraftType": null,
          "origin": null,
          "destination": null,
          "scheduledOut": null,
          "scheduledIn": null,
          "status": "scheduled",
          "cancelled": false,
          "diverted": false,
          "isCodeshare": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let candidate = try decoder.decode(AeroFlightCandidate.self, from: json)
        #expect(candidate.origin == nil)
        #expect(candidate.destination == nil)
    }
}
