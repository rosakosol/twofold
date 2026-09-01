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

    private func flight(
        _ number: String,
        airlineCode: String?,
        name: String? = nil,
        from origin: FlightAirport,
        to destination: FlightAirport
    ) -> Flight {
        Flight(
            travelerIDs: [couple.partnerA.id],
            flightNumberIATA: number,
            airlineName: name,
            airlineCode: airlineCode,
            origin: origin,
            destination: destination
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
