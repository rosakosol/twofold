//
//  FlightStats.swift
//  Twofold
//
//  Flight stats math, for the Stats tab's Flights card, its share card and the full breakdown.
//

import Foundation

/// Everything the passport card, snapshot card, and full-stats page show, computed from real
/// tracked flights — a flight counts here whether or not it has a linked trip (see `init`'s own
/// doc comment for exactly which fields need a trip anyway, and why).
struct FlightStats {
    struct Ranked: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let flightCount: Int
    let userFlightCount: Int
    let partnerFlightCount: Int
    let domesticCount: Int
    let internationalCount: Int
    let longHaulCount: Int
    let shortHaulCount: Int
    let totalDistanceKm: Double
    let averageDistanceKm: Double
    let totalFlightTime: TimeInterval
    let averageFlightTime: TimeInterval
    let longestFlightTime: TimeInterval
    /// e.g. "LAX-MEL" — the specific flight behind `longestFlightTime`, in that flight's own
    /// origin→destination order (unlike `routes` below, which is direction-agnostic for
    /// counting purposes). Nil only when no flight has a resolvable departure/arrival pair.
    let longestFlightRoute: String?
    let airports: [Ranked]
    let airlines: [Ranked]
    let routes: [Ranked]
    let countries: [Ranked]

    var earthMultiple: Double { totalDistanceKm / Geo.earthCircumferenceKm }
    var moonMultiple: Double { totalDistanceKm / Geo.moonDistanceKm }
    var sunMultiple: Double { totalDistanceKm / Geo.sunCircumferenceKm }

    /// Flights longer than this count as long haul.
    private static let longHaulKm = 4_000.0

    /// Every stat here — including domestic/international/countries — is computed straight from
    /// `flights` alone, whether or not any of them are linked to a Trip. Country comes from each
    /// flight's own `FlightAirport.country`, resolved server-side against the `airports`
    /// reference table when the flight was tracked (see add-flight/index.ts) — never from a
    /// linked trip's `Place`. A flight whose airport(s) aren't in that reference table (rare)
    /// just doesn't contribute to these three breakdowns; every other stat below still counts it.
    /// `allFlights` is filtered to the ones actually flown before anything is counted — see
    /// `Flight.hasBeenFlown`. A passport records where you've been, not where you're booked.
    init(flights allFlights: [Flight], couple: Couple) {
        let flights = allFlights.filter(\.hasBeenFlown)
        flightCount = flights.count
        userFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerA.id) }
        partnerFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerB.id) }

        let flightCountries = flights.compactMap { flight -> (String, String)? in
            guard let origin = flight.origin.country, let destination = flight.destination.country else { return nil }
            return (origin, destination)
        }
        domesticCount = flightCountries.count { $0.0 == $0.1 }
        internationalCount = flightCountries.count { $0.0 != $0.1 }
        countries = Self.ranked(flightCountries.flatMap { [$0.0, $0.1] })

        // Each flight's own great-circle distance, not a trip's `effectiveDistanceKm` — "long
        // haul" is naturally about a single flight, and a standalone long flight with no trip
        // attached obviously still qualifies.
        let flightDistances = flights.compactMap { flight -> Double? in
            guard let origin = flight.origin.coordinate, let destination = flight.destination.coordinate else { return nil }
            return Geo.distanceKm(origin, destination)
        }
        longHaulCount = flightDistances.count { $0 > Self.longHaulKm }
        shortHaulCount = flightDistances.count { $0 <= Self.longHaulKm }
        totalDistanceKm = flightDistances.reduce(0, +)
        averageDistanceKm = flightDistances.isEmpty ? 0 : totalDistanceKm / Double(flightDistances.count)

        // From each flight's own scheduled/actual times — a trip's `departureDate`/`arrivalDate`
        // span the whole vacation (e.g. a 14-day trip), not how long any single flight was
        // actually in the air, which is what "Flight time" is supposed to mean.
        let durations = flights.compactMap { flight -> (time: TimeInterval, route: String)? in
            guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else { return nil }
            return (arrival.timeIntervalSince(departure), "\(flight.origin.displayCode)-\(flight.destination.displayCode)")
        }
        totalFlightTime = durations.map(\.time).reduce(0, +)
        averageFlightTime = durations.isEmpty ? 0 : totalFlightTime / Double(durations.count)
        let longest = durations.max { $0.time < $1.time }
        longestFlightTime = longest?.time ?? 0
        longestFlightRoute = longest?.route

        // Canonicalised across the whole set before counting, because the same airport or airline
        // can arrive under more than one identifier — see `airportCanonicaliser`.
        let airportKey = Self.airportCanonicaliser(flights.flatMap { [$0.origin, $0.destination] })
        let airlineKey = Self.airlineCanonicaliser(flights)

        airports = Self.ranked(flights.flatMap { [airportKey($0.origin), airportKey($0.destination)].compactMap { $0 } })
        airlines = Self.ranked(flights.compactMap(airlineKey))
        // Direction-agnostic, so MEL → SIN and SIN → MEL count as one route. A flight with an
        // unresolvable airport at either end contributes no route at all rather than a half-named
        // one — "MEL – —" would rank as its own distinct route, and every such flight would pile
        // into the same fake one.
        routes = Self.ranked(flights.compactMap { flight -> String? in
            guard let origin = airportKey(flight.origin), let destination = airportKey(flight.destination) else { return nil }
            return [origin, destination].sorted().joined(separator: " – ")
        })
    }

    /// One identity per airport, resolved across the whole set of flights rather than per flight.
    ///
    /// An airport is keyed by its IATA code, falling back to ICAO — and that fallback is what
    /// inflated the counts. A flight that resolved only an ICAO code contributed "YMML" while
    /// another through the same airport contributed "MEL", so Melbourne counted as two airports,
    /// two entries in Top Airports, and two separate routes to everywhere it connects. The
    /// reported symptom: three airports flown repeatedly showing as more than three.
    ///
    /// There's no airport table on the device to look codes up in, but the flights themselves
    /// carry the link: any airport that arrives with *both* codes tells us they're the same place.
    /// So one pass records those pairings, and a second resolves every airport through them. An
    /// ICAO code never seen alongside its IATA partner stays as it is — wrong to merge on a guess,
    /// and it's the honest answer for a set of flights that genuinely never identified them
    /// together.
    ///
    /// Not `displayCode`, which exists for *showing* an airport and falls back through `city` to a
    /// literal "—". Both fallbacks corrupt a count: a flight that resolved only a city contributed
    /// "Melbourne" as an airport distinct from another flight's "MEL", and every flight with
    /// nothing resolved contributed the same "—", which then ranked as a real airport someone had
    /// supposedly visited many times.
    private static func airportCanonicaliser(_ airports: [FlightAirport]) -> (FlightAirport) -> String? {
        var canonical: [String: String] = [:]
        for airport in airports {
            guard let iata = normalizedCode(airport.iata) else { continue }
            canonical[iata] = iata
            if let icao = normalizedCode(airport.icao) { canonical[icao] = iata }
        }
        return { airport in
            if let iata = normalizedCode(airport.iata) { return canonical[iata] ?? iata }
            if let icao = normalizedCode(airport.icao) { return canonical[icao] ?? icao }
            return nil
        }
    }

    /// The same idea for airlines, linked through the carrier's name instead of a second code.
    ///
    /// `airlineCode` is whatever the server resolved — `operator_iata` where it exists, ICAO
    /// otherwise — so one carrier can arrive as "SQ" on one flight and "SIA" on another and count
    /// twice. Flights that carry both a code and a name let the two be tied together; the shortest
    /// code wins as the canonical one, which is the IATA form the tailfin logos are keyed on.
    ///
    /// The prefix scrape survives only as a fallback for flights added before `airlineCode` was
    /// populated. It can't be trusted as a primary key: `flightNumber` is
    /// `marketingFlightNumber ?? flightNumberIATA`, so a codeshare reports the *marketing*
    /// carrier's prefix while a non-codeshare on the same airline reports its own — which is how
    /// five flights across three airlines once came out as four.
    private static func airlineCanonicaliser(_ flights: [Flight]) -> (Flight) -> String? {
        var byName: [String: String] = [:]
        for flight in flights {
            guard let code = rawAirlineKey(for: flight),
                  let name = flight.airlineName?.trimmingCharacters(in: .whitespaces).lowercased(),
                  !name.isEmpty else { continue }
            if let existing = byName[name], existing.count <= code.count { continue }
            byName[name] = code
        }
        return { flight in
            guard let code = rawAirlineKey(for: flight) else { return nil }
            guard let name = flight.airlineName?.trimmingCharacters(in: .whitespaces).lowercased() else { return code }
            return byName[name] ?? code
        }
    }

    private static func rawAirlineKey(for flight: Flight) -> String? {
        if let code = flight.airlineCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty {
            return code.uppercased()
        }
        let prefix = flight.flightNumber.prefix { $0.isLetter }
        return prefix.isEmpty ? nil : prefix.uppercased()
    }

    private static func normalizedCode(_ code: String?) -> String? {
        guard let trimmed = code?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    private static func ranked(_ names: [String]) -> [Ranked] {
        Dictionary(grouping: names, by: { $0 })
            .map { Ranked(name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
