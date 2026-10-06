//
//  DemoData.swift
//  Twofold
//
//  The sample couple behind `-demoMode` (see App/DemoMode.swift): Sam, the person holding the
//  phone, in Melbourne, and Alex in Rome. Their story matches the website's copy: Alex is in the
//  air on the way home, they're 15,966 km apart, on a 47-day streak, and their first date was in
//  Rome. Dates are relative to now, so every screenshot looks current.
//

#if DEBUG
import SwiftUI
import UIKit

enum DemoData {
    static let melbourne = Place(city: "Melbourne", country: "Australia", iataCode: "MEL", latitude: -37.8136, longitude: 144.9631, timeZoneIdentifier: "Australia/Melbourne")
    static let rome = Place(city: "Rome", country: "Italy", iataCode: "FCO", latitude: 41.9028, longitude: 12.4964, timeZoneIdentifier: "Europe/Rome")
    static let doha = Place(city: "Doha", country: "Qatar", iataCode: "DOH", latitude: 25.2854, longitude: 51.5310, timeZoneIdentifier: "Asia/Qatar")
    static let lisbon = Place(city: "Lisbon", country: "Portugal", iataCode: "LIS", latitude: 38.7223, longitude: -9.1393, timeZoneIdentifier: "Europe/Lisbon")
    static let tokyo = Place(city: "Tokyo", country: "Japan", iataCode: "HND", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo")
    // Three places in Rome rather than the city, so the memories map shows three photo pins
    // there instead of one.
    static let trattoria = Place(city: "Rome", country: "Italy", latitude: 41.8975, longitude: 12.5146, timeZoneIdentifier: "Europe/Rome")
    static let villaBorghese = Place(city: "Rome", country: "Italy", latitude: 41.9142, longitude: 12.4923, timeZoneIdentifier: "Europe/Rome")
    static let trastevere = Place(city: "Rome", country: "Italy", latitude: 41.8897, longitude: 12.4695, timeZoneIdentifier: "Europe/Rome")

    static let sam = Person(name: "Sam", homeCity: melbourne, accentColor: Person.palette[0])
    static let alex = Person(name: "Alex", homeCity: rome, accentColor: Person.palette[1])

    private static let calendar = Calendar.current
    private static func days(_ n: Int, hours: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: n, to: .now) ?? .now
        return calendar.date(byAdding: .hour, value: hours, to: day) ?? day
    }

    static let couple = Couple(
        partnerA: sam,
        partnerB: alex,
        startedDatingOn: calendar.date(byAdding: .month, value: -27, to: .now) ?? .now,
        connectedAt: calendar.date(byAdding: .month, value: -14, to: .now),
        maxDistanceKm: 15_966
    )

    private static func airport(_ place: Place, name: String) -> FlightAirport {
        FlightAirport(iata: place.iataCode, name: name, city: place.city, timezone: place.timeZoneIdentifier, latitude: place.latitude, longitude: place.longitude, country: place.country)
    }
    private static let fco = airport(rome, name: "Leonardo da Vinci-Fiumicino")
    private static let doh = airport(doha, name: "Hamad International")
    private static let mel = airport(melbourne, name: "Melbourne Airport")
    private static let lis = airport(lisbon, name: "Humberto Delgado")

    // MARK: Alex on the way home: Rome to Doha (landed), Doha to Melbourne (in the air, ~86%)

    static let reunionTripID = UUID()

    static let romeToDoha = Flight(
        tripID: reunionTripID, travelerIDs: [alex.id], faFlightID: "QTR116-demo",
        flightNumberIATA: "QR116", airlineName: "Qatar Airways", airlineCode: "QR",
        origin: fco, destination: doh, aircraftType: "A350-900",
        scheduledOut: days(-1, hours: -9), scheduledIn: days(-1, hours: -3),
        actualOut: days(-1, hours: -9), actualOff: days(-1, hours: -9), actualOn: days(-1, hours: -3), actualIn: days(-1, hours: -3),
        terminalOrigin: "3", gateOrigin: "E14", status: .arrived, trackingEnabled: false
    )

    static let dohaToMelbourne: Flight = {
        let departure = calendar.date(byAdding: .minute, value: -(11 * 60 + 40), to: .now) ?? .now
        let arrival = calendar.date(byAdding: .minute, value: 108, to: .now) ?? .now
        return Flight(
            tripID: reunionTripID, travelerIDs: [alex.id], faFlightID: "QTR904-demo",
            flightNumberIATA: "QR904", airlineName: "Qatar Airways", airlineCode: "QR",
            origin: doh, destination: mel, aircraftType: "A350-1000", registration: "A7-ANA",
            scheduledOut: departure, scheduledIn: arrival,
            estimatedIn: arrival, actualOut: departure, actualOff: departure,
            terminalOrigin: "1", gateOrigin: "C22", terminalDestination: "2", gateDestination: "9", baggageClaim: "4",
            status: .inAir,
            positionLatitude: -27.9, positionLongitude: 129.6, positionAltitude: 39_000,
            positionGroundspeed: 498, positionHeading: 128, positionUpdatedAt: .now,
            lastRefreshedAt: .now
        )
    }()

    static let reunionTrip = Trip(
        id: reunionTripID, travelerIDs: [alex.id], origin: rome, destination: melbourne,
        departureDate: romeToDoha.scheduledDeparture, arrivalDate: dohaToMelbourne.scheduledArrival,
        category: .reunion, distanceKm: 15_966, flights: [romeToDoha, dohaToMelbourne],
        notes: "Coming home to you"
    )

    // MARK: The rest of their story

    static let tokyoTrip = Trip(
        travelerIDs: [sam.id, alex.id], origin: melbourne, destination: tokyo,
        departureDate: days(58), arrivalDate: days(66),
        category: .together, distanceKm: 8_150, notes: "Cherry blossoms, finally"
    )

    private static let samToRomeOut = Flight(
        travelerIDs: [sam.id], flightNumberIATA: "QR905", airlineName: "Qatar Airways", airlineCode: "QR",
        origin: mel, destination: doh, scheduledOut: days(-124), scheduledIn: days(-124, hours: 14),
        actualOut: days(-124), actualIn: days(-124, hours: 14), status: .arrived, trackingEnabled: false
    )
    static let romeReunion = Trip(
        travelerIDs: [sam.id], origin: melbourne, destination: rome,
        departureDate: days(-124), arrivalDate: days(-123),
        category: .reunion, distanceKm: 15_966, flights: [samToRomeOut], notes: "Two weeks in Rome"
    )

    private static let lisbonFlight = Flight(
        travelerIDs: [alex.id], flightNumberIATA: "TP837", airlineName: "TAP Air Portugal", airlineCode: "TP",
        origin: fco, destination: lis, scheduledOut: days(-212), scheduledIn: days(-212, hours: 3),
        actualOut: days(-212), actualIn: days(-212, hours: 3), status: .arrived, trackingEnabled: false
    )
    static let lisbonTrip = Trip(
        travelerIDs: [sam.id, alex.id], origin: rome, destination: lisbon,
        departureDate: days(-212), arrivalDate: days(-205),
        category: .together, distanceKm: 1_860, flights: [lisbonFlight], notes: "After 62 days apart"
    )

    static let alexToMelbourne = Trip(
        travelerIDs: [alex.id], origin: rome, destination: melbourne,
        departureDate: days(-301), arrivalDate: days(-300),
        category: .reunion, distanceKm: 15_966, notes: "Your first Australian winter"
    )

    static let trips = [reunionTrip, tokyoTrip, romeReunion, lisbonTrip, alexToMelbourne]
    static let flights = [dohaToMelbourne, romeToDoha, samToRomeOut, lisbonFlight]

    // MARK: Memories, with the bundled photos written to disk so they load like real ones

    static let firstDateID = UUID()

    static func memories() -> [Memory] {
        [
            Memory(id: firstDateID, title: "Our first date", place: trattoria, date: days(-820),
                   note: "You were wearing a red sundress and I couldn't stop looking at you.",
                   photos: photo("where-we-met")),
            Memory(title: "Sunset in Lisbon", place: lisbon, date: days(-208),
                   note: "Sixty-two days apart, and then this. Neither of us wanted to leave the beach.",
                   photos: photo("sunset")),
            Memory(title: "Walking Villa Borghese", place: villaBorghese, date: days(-118),
                   note: "The long way round, on purpose.",
                   photos: photo("park")),
            Memory(title: "Last coffee before the airport", place: melbourne, date: days(-296),
                   note: "Neither of us said much. We didn't need to.", photoSeed: 4),
            Memory(title: "Trastevere at midnight", place: trastevere, date: days(-121),
                   note: "Gelato, cobblestones, and you laughing at my Italian.", photoSeed: 2),
        ]
    }

    /// One bundled image, written once into Caches so it can be a `file://` photo URL, the same
    /// shape a memory that hasn't synced yet uses.
    private static func photo(_ asset: String) -> [MemoryPhoto] {
        guard let image = UIImage(named: asset), let data = image.jpegData(compressionQuality: 0.9),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return [] }
        let url = caches.appendingPathComponent("demo-\(asset).jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }
        return [MemoryPhoto(id: UUID(), path: "demo/\(asset)", url: url)]
    }

    /// The weather WeatherKit would report, which the simulator cannot fetch: partly cloudy in
    /// Rome, clear in Melbourne.
    static func weather(for place: Place) -> CurrentWeatherReading {
        let timeZone = place.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let hour = TimeMath.hourFraction(in: timeZone, at: .now)
        let isDay = hour >= 6 && hour < 18
        if place.city == "Rome" {
            return CurrentWeatherReading(symbolName: isDay ? "cloud.sun" : "cloud.moon", temperatureC: isDay ? 21 : 16, isDaylight: isDay)
        }
        return CurrentWeatherReading(symbolName: isDay ? "sun.max" : "moon.stars", temperatureC: isDay ? 19 : 13, isDaylight: isDay)
    }

    static let streak = 47
    static let dailyQuestion = "What's a small thing I do that makes you feel loved?"
}
#endif
