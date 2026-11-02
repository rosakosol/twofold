//
//  FlightAirportLocalTimeTests.swift
//  TwofoldTests
//
//  Every flight time is that airport's local time, because that is what the boarding pass and the
//  departure board say. The tracking screen kept that rule; the Lock Screen, the Dynamic Island and
//  the flight tracking widget didn't, and showed the phone's own clock (FLT-5). The tracking
//  screen's own refetch also threw away the zones the app had worked out (FLT-6).
//
//  UA60 leaves San Francisco at 11:20pm on 11 August. On a phone in Melbourne that is 4:20pm on the
//  12th — a different time and a different day, across the date line.
//

import Testing
import Foundation
@testable import Twofold

struct FlightAirportLocalTimeTests {

    private static let departure = ISO8601DateFormatter().date(from: "2026-08-11T23:20:00-07:00")!
    private static let losAngeles = "America/Los_Angeles"
    private static let melbourne = TimeZone(identifier: "Australia/Melbourne")!
    private static let usEnglish = Locale(identifier: "en_US")

    private func ua60(originZone: String? = losAngeles, destinationZone: String? = nil) -> Flight {
        Flight(
            faFlightID: "UAL60-1",
            flightNumberIATA: "UA60", airlineCode: "UA",
            origin: FlightAirport(iata: "SFO", city: "San Francisco", timezone: originZone),
            destination: FlightAirport(iata: "MEL", city: "Melbourne", timezone: destinationZone),
            scheduledOut: Self.departure,
            scheduledIn: Self.departure.addingTimeInterval(15 * 3600 + 15 * 60),
            status: .boarding
        )
    }

    // MARK: - FLT-5: the extension's formatting

    @Test("the Lock Screen's departure time is San Francisco's 11:20 PM, not the phone's")
    func timeIsInTheAirportsZone() {
        let text = Self.departure.formatted(FlightLocalTime.timeStyle(Self.losAngeles, locale: Self.usEnglish))
        #expect(text.contains("11:20"), "got \(text)")
        #expect(text.contains("PM"), "got \(text)")
    }

    @Test("travel day is the airport's day: a morning and a late-night departure share one in LA")
    func travelDayIsTheAirportsDay() {
        // 00:30 and 23:20 on the 11th in Los Angeles. In any other zone — the phone's own in
        // Melbourne, or UTC — they straddle a midnight.
        let earlyThatDay = ISO8601DateFormatter().date(from: "2026-08-11T00:30:00-07:00")!
        #expect(FlightLocalTime.isSameDay(earlyThatDay, Self.departure, timeZoneID: Self.losAngeles))
        #expect(!FlightLocalTime.isSameDay(earlyThatDay, Self.departure, timeZoneID: "Australia/Melbourne"))
    }

    @Test("an unknown or missing zone falls back to the phone's")
    func unknownZoneFallsBack() {
        #expect(FlightLocalTime.timeZone(nil) == .current)
        #expect(FlightLocalTime.timeZone("Not/AZone") == .current)
        #expect(FlightLocalTime.timeZone(Self.losAngeles).identifier == Self.losAngeles)
    }

    // MARK: - FLT-5: the app hands the extension the zones

    @Test("a Live Activity carries each airport's zone, or home's where the airport's is unknown")
    func attributesCarryTheZones() {
        let participants = JourneyParticipants(travelerName: "Alex", partnerName: "Sam", viewerIsTraveler: false)
        let attributes = ua60().makeJourneyActivityAttributes(participants: participants, homeTimeZone: Self.melbourne)
        #expect(attributes.originTimeZoneID == Self.losAngeles)
        #expect(attributes.destinationTimeZoneID == "Australia/Melbourne")
    }

    @Test("the widget snapshot carries the same zones")
    func snapshotCarriesTheZones() {
        let info = WidgetSnapshotWriter.flightInfo(for: ua60(), currentUserID: UUID(), travellerIDs: [], homeTimeZone: Self.melbourne)
        #expect(info.originTimeZoneID == Self.losAngeles)
        #expect(info.destinationTimeZoneID == "Australia/Melbourne")
    }

    @Test("a card started before the zones existed still decodes")
    func olderAttributesStillDecode() throws {
        let json = """
        {"flightID":"\(UUID().uuidString)","travelerName":"Alex","flightNumber":"UA60","originCode":"SFO","destinationCode":"MEL"}
        """
        let decoded = try JSONDecoder().decode(JourneyActivityAttributes.self, from: Data(json.utf8))
        #expect(decoded.originTimeZoneID == nil)
    }

    // MARK: - FLT-6: a refetch keeps the zones already resolved

    @Test("a fresh row with no zones keeps the ones the app had resolved for the same airports")
    func refetchKeepsResolvedZones() {
        let resolved = ua60(originZone: Self.losAngeles, destinationZone: "Australia/Melbourne")
        let fresh = ua60(originZone: nil, destinationZone: nil)

        let merged = fresh.keepingTimeZones(from: resolved)
        #expect(merged.origin.timezone == Self.losAngeles)
        #expect(merged.destination.timezone == "Australia/Melbourne")
    }

    @Test("but a zone the row does carry wins, and a different airport takes nothing")
    func refetchDoesNotOverrideOrCrossAirports() {
        let resolved = ua60(originZone: "America/Denver", destinationZone: "Australia/Melbourne")
        var fresh = ua60(originZone: Self.losAngeles, destinationZone: nil)
        fresh.destination.iata = "SYD"

        let merged = fresh.keepingTimeZones(from: resolved)
        #expect(merged.origin.timezone == Self.losAngeles)
        #expect(merged.destination.timezone == nil)
    }
}
