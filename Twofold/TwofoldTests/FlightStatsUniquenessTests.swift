//
//  FlightStatsUniquenessTests.swift
//  TwofoldTests
//
//  Airports, airlines, countries and routes are reported as counts of *distinct* things — three
//  airports flown through many times each is three airports, not nine. Nothing surfaces when that
//  goes wrong: an inflated number is still a plausible number.
//

import Testing
import Foundation
@testable import Twofold

struct FlightStatsUniquenessTests {

    private let couple = Couple(
        partnerA: Person(name: "Alex", accentColor: Person.palette[0]),
        partnerB: Person(name: "Sam", accentColor: Person.palette[1]),
        startedDatingOn: Date(timeIntervalSince1970: 1_600_000_000)
    )

    private func airport(iata: String? = nil, icao: String? = nil, city: String, country: String = "Australia") -> FlightAirport {
        FlightAirport(iata: iata, icao: icao, name: nil, city: city, timezone: nil, latitude: nil, longitude: nil, country: country)
    }

    /// Defaults to a flight that has already been taken, since that's what stats count — see
    /// `Flight.hasBeenFlown`. Tests that care about the other states say so explicitly.
    private func flight(
        _ number: String,
        airlineCode: String?,
        name: String? = nil,
        from origin: FlightAirport,
        to destination: FlightAirport,
        departedAgo: TimeInterval = 8 * 86_400,
        status: FlightStatus = .arrived,
        cancelled: Bool = false
    ) -> Flight {
        Flight(
            travelerIDs: [couple.partnerA.id],
            flightNumberIATA: number,
            airlineName: name,
            airlineCode: airlineCode,
            origin: origin,
            destination: destination,
            scheduledOut: Date.now.addingTimeInterval(-departedAgo),
            scheduledIn: Date.now.addingTimeInterval(-departedAgo + 8 * 3600),
            cancelled: cancelled,
            status: status
        )
    }

    private func stats(_ flights: [Flight]) -> FlightStats {
        FlightStats(flights: flights, couple: couple)
    }

    // MARK: - The reported case

    /// Three airports flown through repeatedly is three airports.
    @Test("flying the same airports many times still counts them once each")
    func repeatedAirportsCountOnce() {
        let mel = airport(iata: "MEL", city: "Melbourne")
        let sin = airport(iata: "SIN", city: "Singapore", country: "Singapore")
        let hkg = airport(iata: "HKG", city: "Hong Kong", country: "Hong Kong")
        let result = stats([
            flight("SQ208", airlineCode: "SQ", from: mel, to: sin),
            flight("SQ207", airlineCode: "SQ", from: sin, to: mel),
            flight("CX105", airlineCode: "CX", from: mel, to: hkg),
            flight("CX104", airlineCode: "CX", from: hkg, to: mel),
            flight("SQ872", airlineCode: "SQ", from: sin, to: hkg),
        ])
        #expect(result.airports.count == 3, "MEL, SIN, HKG — flown ten times between them, but three airports")
        #expect(result.airlines.count == 2, "SQ and CX")
        #expect(result.countries.count == 3, "Australia, Singapore, Hong Kong")
        #expect(result.routes.count == 3, "MEL–SIN, MEL–HKG, SIN–HKG, each flown both ways")
    }

    // MARK: - The same thing under two identifiers

    /// The airport key is `iata ?? icao`, so an airport arriving with only an ICAO code counts
    /// separately from the same airport arriving with its IATA one.
    ///
    /// Real rows carry both (confirmed against production: every flight has origin_iata *and*
    /// origin_icao), which is what makes this recoverable — the flights that carry both teach the
    /// pairing, and an ICAO-only one is resolved through it.
    @Test("one airport under both an IATA and an ICAO code is still one airport")
    func mixedAirportCodesCollapse() {
        let melFull = airport(iata: "MEL", icao: "YMML", city: "Melbourne")
        let melByICAO = airport(icao: "YMML", city: "Melbourne")
        let sin = airport(iata: "SIN", icao: "WSSS", city: "Singapore", country: "Singapore")
        let result = stats([
            flight("SQ208", airlineCode: "SQ", from: melFull, to: sin),
            flight("SQ207", airlineCode: "SQ", from: sin, to: melByICAO),
        ])
        #expect(result.airports.count == 2, "Melbourne and Singapore, however Melbourne was identified")
        #expect(result.routes.count == 1, "one route, flown both ways")
    }

    /// Same shape for airlines: `airlineCode` is the operator code the server resolved, IATA where
    /// it exists and ICAO otherwise, so one carrier can arrive under either. The carrier's name is
    /// what ties them together — real rows carry it alongside the code.
    @Test("one airline under both an IATA and an ICAO code is still one airline")
    func mixedAirlineCodesCollapse() {
        let mel = airport(iata: "MEL", icao: "YMML", city: "Melbourne")
        let sin = airport(iata: "SIN", icao: "WSSS", city: "Singapore", country: "Singapore")
        let result = stats([
            flight("SQ208", airlineCode: "SQ", name: "Singapore Airlines", from: mel, to: sin),
            flight("SQ207", airlineCode: "SIA", name: "Singapore Airlines", from: sin, to: mel),
        ])
        #expect(result.airlines.count == 1, "Singapore Airlines, however it was identified")
        #expect(result.airlines.first?.name == "SQ", "the IATA form wins, since the tailfin logos are keyed on it")
    }

    // MARK: - What must stay separate

    @Test("genuinely different airports and airlines are not merged")
    func distinctThingsStayDistinct() {
        let mel = airport(iata: "MEL", city: "Melbourne")
        let syd = airport(iata: "SYD", city: "Sydney")
        let sin = airport(iata: "SIN", city: "Singapore", country: "Singapore")
        let result = stats([
            flight("SQ208", airlineCode: "SQ", from: mel, to: sin),
            flight("QF81", airlineCode: "QF", from: syd, to: sin),
        ])
        #expect(result.airports.count == 3)
        #expect(result.airlines.count == 2)
        #expect(result.routes.count == 2)
    }

    /// An airport with neither code contributes nothing rather than becoming a shared phantom
    /// entry every unresolvable flight piles into.
    @Test("an unidentifiable airport is not counted as an airport")
    func unidentifiableAirportsAreSkipped() {
        let mel = airport(iata: "MEL", city: "Melbourne")
        let unknown = airport(city: "Somewhere")
        let result = stats([flight("XX1", airlineCode: "XX", from: mel, to: unknown)])
        #expect(result.airports.count == 1)
        #expect(result.routes.isEmpty, "a route needs both ends identified")
    }
}

/// Stats count where you've been, not where you're booked. Every flight row used to count
/// regardless of status, so a trip booked for next month made its destination an airport you'd
/// visited and its distance part of how far you'd travelled.
struct FlightStatsFlownOnlyTests {

    private let couple = Couple(
        partnerA: Person(name: "Alex", accentColor: Person.palette[0]),
        partnerB: Person(name: "Sam", accentColor: Person.palette[1]),
        startedDatingOn: Date(timeIntervalSince1970: 1_600_000_000)
    )

    private func airport(_ iata: String, _ city: String, country: String = "Australia") -> FlightAirport {
        FlightAirport(iata: iata, icao: nil, name: nil, city: city, timezone: nil, latitude: nil, longitude: nil, country: country)
    }

    private func flight(
        to destination: FlightAirport,
        departsIn: TimeInterval,
        status: FlightStatus,
        cancelled: Bool = false
    ) -> Flight {
        Flight(
            travelerIDs: [couple.partnerA.id],
            flightNumberIATA: "QF1",
            airlineName: "Qantas",
            airlineCode: "QF",
            origin: airport("MEL", "Melbourne"),
            destination: destination,
            scheduledOut: Date.now.addingTimeInterval(departsIn),
            scheduledIn: Date.now.addingTimeInterval(departsIn + 8 * 3600),
            cancelled: cancelled,
            status: status
        )
    }

    private func stats(_ flights: [Flight]) -> FlightStats { FlightStats(flights: flights, couple: couple) }

    @Test("a flight booked for next month isn't somewhere you've been")
    func upcomingFlightsAreExcluded() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: 30 * 86_400, status: .scheduled)])
        #expect(result.flightCount == 0)
        #expect(result.airports.isEmpty, "Tokyo isn't an airport you've visited yet")
        #expect(result.countries.isEmpty)
        #expect(result.totalDistanceKm == 0)
    }

    @Test("a cancelled flight is a journey nobody took")
    func cancelledFlightsAreExcluded() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -30 * 86_400, status: .cancelled)])
        #expect(result.flightCount == 0)
        #expect(result.airports.isEmpty)
    }

    /// Cancelled wins over a past arrival time — the clock says it landed, the status says it never
    /// left.
    @Test("the cancelled flag beats the clock")
    func cancelledFlagWinsOverTimestamps() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -30 * 86_400, status: .arrived, cancelled: true)])
        #expect(result.flightCount == 0)
    }

    @Test("a flight already taken counts")
    func pastFlightsAreCounted() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -30 * 86_400, status: .arrived)])
        #expect(result.flightCount == 1)
        #expect(result.airports.count == 2)
    }

    /// You flew — just not to the airport on the ticket.
    @Test("a diverted flight still counts")
    func divertedFlightsAreCounted() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -2 * 86_400, status: .diverted)])
        #expect(result.flightCount == 1)
    }

    /// Tracking stops when the provider stops reporting, so a flight that landed isn't always
    /// *marked* landed. The clock decides when the status doesn't.
    @Test("a past flight still marked scheduled counts, because the clock says it flew")
    func staleStatusFallsBackToTheClock() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -10 * 86_400, status: .scheduled)])
        #expect(result.flightCount == 1)
    }

    /// Taking off isn't arriving. A flight in the air can divert, turn back, or land somewhere
    /// else, so it isn't a journey taken — or an airport visited — until it's down.
    @Test("a flight still in the air doesn't count yet")
    func inAirFlightsAreNotCountedYet() {
        let result = stats([flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -2 * 3600, status: .inAir)])
        #expect(result.flightCount == 0)
    }

    @Test("mixing flown and unflown counts only the flown")
    func onlyFlownFlightsAreCounted() {
        let result = stats([
            flight(to: airport("HND", "Tokyo", country: "Japan"), departsIn: -30 * 86_400, status: .arrived),
            flight(to: airport("SIN", "Singapore", country: "Singapore"), departsIn: -10 * 86_400, status: .arrived),
            flight(to: airport("JFK", "New York", country: "United States"), departsIn: 20 * 86_400, status: .scheduled),
            flight(to: airport("LHR", "London", country: "United Kingdom"), departsIn: -5 * 86_400, status: .cancelled),
        ])
        #expect(result.flightCount == 2, "two flown, one upcoming, one cancelled")
        #expect(result.airports.count == 3, "MEL, HND, SIN")
    }
}
