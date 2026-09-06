//
//  AddFlightSuggestionTests.swift
//  TwofoldTests
//
//  The two pieces of Add Flight that were guessing.
//
//  The typed departure date parsed fine and then had nowhere to go — nothing on screen advanced,
//  so "30/9" looked like an input the app ignored. The parsing is asserted here because the fix
//  depends on it: the screen now shows the date it read back, which is only worth showing if it is
//  right, and "10/5" means different months in different countries.
//
//  The airport suggestions were worse than wrong, they were arbitrary. The old code fetched the
//  first 200 rows the table happened to return and ranked *those* by distance, so "airports near
//  Melbourne" was drawn from an unordered slice of 6,000 — the list opened on Alexandra, New
//  Zealand and Amata, Northern Territory. Ranking is now asserted against real airport rows.
//

import Testing
import CoreLocation
import Foundation
@testable import Twofold

struct AddFlightSuggestionTests {

    // MARK: - Typing a departure date

    /// The reported case, in the locale the app is used in.
    @Test("30/9 reads as the 30th of September")
    func slashDateParses() throws {
        let parsed = try #require(AddFlightDateStepView.date(from: "30/9"))
        let parts = Calendar.current.dateComponents([.day, .month], from: parsed)
        #expect(parts.day == 30)
        #expect(parts.month == 9)
    }

    @Test("a written date and a weekday both parse")
    func otherFormsParse() throws {
        let written = try #require(AddFlightDateStepView.date(from: "30 September"))
        #expect(Calendar.current.component(.day, from: written) == 30)
        #expect(AddFlightDateStepView.date(from: "Friday") != nil)
    }

    /// A departure date is in the future. A bare day and month has to resolve forward, or searching
    /// "10/5" in June returns nothing and looks like a broken search rather than a past date.
    @Test("a bare day and month resolves to a date that hasn't passed")
    func bareDatesResolveForward() throws {
        let parsed = try #require(AddFlightDateStepView.date(from: "30/9"))
        // Same day counts: a flight later today is still ahead.
        #expect(parsed >= Calendar.current.startOfDay(for: .now))
    }

    /// Half-typed text must not be offered as a date. The field parses on every keystroke, and "3"
    /// on the way to "30/9" resolving to something would put a wrong date in front of someone
    /// mid-word.
    @Test("incomplete text parses to nothing")
    func partialInputIsNotADate() {
        #expect(AddFlightDateStepView.date(from: "") == nil)
        #expect(AddFlightDateStepView.date(from: "   ") == nil)
        #expect(AddFlightDateStepView.date(from: "3") == nil)
    }

    // MARK: - Which airports to suggest

    private func airport(_ iata: String, _ name: String, city: String?, country: String, tz: String?, _ lat: Double, _ lon: Double) -> Airport {
        Airport(iata: iata, icao: nil, name: name, city: city, country: country, latitude: lat, longitude: lon, timeZoneIdentifier: tz)
    }

    /// Real rows, real coordinates — the ones that made the destination list read badly.
    private var australianAirports: [Airport] {
        [
            airport("SYD", "Sydney Kingsford Smith International Airport", city: "Sydney", country: "Australia", tz: "Australia/Sydney", -33.9461, 151.1772),
            airport("CBR", "Canberra International Airport", city: "Canberra", country: "Australia", tz: "Australia/Sydney", -35.3069, 149.1950),
            airport("HBA", "Hobart International Airport", city: "Hobart", country: "Australia", tz: "Australia/Hobart", -42.8361, 147.5103),
            airport("TUM", "Tumut Airport", city: nil, country: "Australia", tz: nil, -35.2628, 148.2411),
            airport("GUL", "Goulburn Airport", city: "Goulburn", country: "Australia", tz: "Australia/Sydney", -34.8103, 149.7261),
            airport("XRH", "RAAF Base Richmond", city: "Richmond", country: "Australia", tz: "Australia/Sydney", -33.6006, 150.7811),
            // Same state as the departure — must not be offered at all.
            airport("AVV", "Avalon Airport", city: "Avalon", country: "Australia", tz: "Australia/Melbourne", -38.0394, 144.4694),
            airport("MEB", "Melbourne Essendon Airport", city: "Melbourne", country: "Australia", tz: "Australia/Melbourne", -37.7281, 144.9019),
        ]
    }

    private var melbourne: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: -37.6733, longitude: 144.8433) }

    /// An "International" airport leads, ahead of nearer strips. Goulburn and Tumut are closer to
    /// Melbourne than Sydney is, and sorting on distance alone put them first.
    @Test("real airports outrank nearer airstrips")
    func internationalAirportsComeFirst() {
        let ranked = FlightSearchIndex.rankAsDestinationsForTesting(australianAirports, from: melbourne, limit: 8)
        let top = ranked.prefix(3).map(\.iata)
        #expect(top == ["CBR", "HBA", "SYD"], "got \(ranked.map(\.iata))")
        // Named-city airstrips still appear, below the real airports rather than above them.
        let goulburn = try? #require(ranked.firstIndex { $0.iata == "GUL" })
        let sydney = try? #require(ranked.firstIndex { $0.iata == "SYD" })
        #expect((goulburn ?? 0) > (sydney ?? 0))
    }

    /// The negative control for the assertion above: Goulburn and Tumut really are nearer, so the
    /// ordering is not distance falling out by accident.
    @Test("the preferred airports are not simply the closest ones")
    func rankingIsNotJustDistance() {
        let byDistance = australianAirports
            .filter { $0.timeZoneIdentifier != "Australia/Melbourne" }
            .sorted { Geo.distanceKm(melbourne, $0.coordinate) < Geo.distanceKm(melbourne, $1.coordinate) }
        #expect(byDistance.first?.iata == "TUM", "got \(byDistance.map(\.iata)) — distance no longer puts an airstrip first")
    }

    /// A military field carrying "International" in its name must not lead the list. RAAF Richmond
    /// is the local case; Yuma MCAS is the one that actually appeared in the real US data.
    @Test("military fields don't lead the list")
    func militaryFieldsAreNotPreferred() {
        let ranked = FlightSearchIndex.rankAsDestinationsForTesting(
            [
                airport("XRH", "RAAF Base Richmond", city: "Richmond", country: "Australia", tz: "Australia/Sydney", -33.6006, 150.7811),
                airport("YUM", "Yuma MCAS/Yuma International Airport", city: "Yuma", country: "United States", tz: nil, 32.6566, -114.6060),
                airport("SYD", "Sydney Kingsford Smith International Airport", city: "Sydney", country: "Australia", tz: "Australia/Sydney", -33.9461, 151.1772),
            ],
            from: melbourne,
            limit: 3
        )
        #expect(ranked.first?.iata == "SYD", "got \(ranked.map(\.iata))")
    }

    /// Nothing without a name to show gets promoted over somewhere with one.
    @Test("an airport with no city sorts last")
    func namelessAirportsSortLast() {
        let ranked = FlightSearchIndex.rankAsDestinationsForTesting(australianAirports, from: melbourne, limit: 8)
        #expect(ranked.last?.iata == "TUM", "got \(ranked.map(\.iata))")
    }
}
