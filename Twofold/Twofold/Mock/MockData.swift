//
//  MockData.swift
//  Twofold
//
//  Sample data standing in for a real backend. Numbers are lifted from the
//  README's own examples so the UI matches the product narrative.
//

import Foundation

enum MockData {
    static let melbourne = Place(city: "Melbourne", country: "Australia", iataCode: "MEL", latitude: -37.8136, longitude: 144.9631)
    static let singapore = Place(city: "Singapore", country: "Singapore", iataCode: "SIN", latitude: 1.3521, longitude: 103.8198)
    static let bangkok = Place(city: "Bangkok", country: "Thailand", iataCode: "BKK", latitude: 13.7563, longitude: 100.5018)
    static let tokyo = Place(city: "Tokyo", country: "Japan", iataCode: "HND", latitude: 35.6762, longitude: 139.6503)

    static let dara = Person(name: "Dara", homeCity: singapore, accentColor: Person.palette[0])
    static let rosa = Person(name: "Rosa", homeCity: melbourne, accentColor: Person.palette[1])

    static let couple = Couple(
        partnerA: dara,
        partnerB: rosa,
        startedDatingOn: Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .now
    )

    /// The active reunion flight shown on the Globe/Flight tracking screens: Dara flying SIN -> MEL, currently in the air.
    static let activeFlight: Flight = {
        let departure = Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now
        let arrival = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now
        return Flight(
            flightNumber: "QF35",
            origin: singapore,
            destination: melbourne,
            status: .inAir,
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            progress: 0.45,
            timeline: [
                FlightTimelineEvent(kind: .departed, time: departure, isComplete: true),
                FlightTimelineEvent(kind: .inAir, time: departure.addingTimeInterval(3 * 3600), isComplete: true),
                FlightTimelineEvent(kind: .landingSoon, time: arrival.addingTimeInterval(-1800), isComplete: false),
                FlightTimelineEvent(kind: .arrived, time: arrival, isComplete: false),
            ]
        )
    }()

    static let reunionTrip = Trip(
        travelerID: dara.id,
        origin: singapore,
        destination: melbourne,
        departureDate: activeFlight.scheduledDeparture,
        arrivalDate: activeFlight.scheduledArrival,
        category: .seeingEachOther,
        distanceKm: 6060,
        flight: activeFlight
    )

    static let pastLandedFlight = Flight(
        flightNumber: "QF34",
        origin: melbourne,
        destination: singapore,
        status: .arrived,
        scheduledDeparture: Calendar.current.date(byAdding: .day, value: -80, to: .now) ?? .now,
        scheduledArrival: Calendar.current.date(byAdding: .day, value: -80, to: .now) ?? .now,
        progress: 1,
        timeline: []
    )

    static let pastTrip = Trip(
        travelerID: rosa.id,
        origin: melbourne,
        destination: singapore,
        departureDate: pastLandedFlight.scheduledDeparture,
        arrivalDate: pastLandedFlight.scheduledArrival,
        category: .seeingEachOther,
        distanceKm: 6060,
        flight: pastLandedFlight,
        notes: "You flew to Dara"
    )

    static let togetherTrip = Trip(
        travelerID: dara.id,
        origin: singapore,
        destination: bangkok,
        departureDate: DateComponents(calendar: .current, year: 2024, month: 3, day: 2).date ?? .now,
        arrivalDate: DateComponents(calendar: .current, year: 2024, month: 3, day: 6).date ?? .now,
        category: .together,
        distanceKm: 1435,
        notes: "Weekend together"
    )

    static let personalTrip = Trip(
        travelerID: dara.id,
        origin: singapore,
        destination: tokyo,
        departureDate: Calendar.current.date(byAdding: .day, value: -160, to: .now) ?? .now,
        arrivalDate: Calendar.current.date(byAdding: .day, value: -158, to: .now) ?? .now,
        category: .personal,
        distanceKm: 5300,
        notes: "Business trip"
    )

    static let trips: [Trip] = [reunionTrip, pastTrip, togetherTrip, personalTrip]

    static let memories: [Memory] = [
        Memory(
            title: "First night in Singapore",
            emoji: "❤️",
            place: singapore,
            date: DateComponents(calendar: .current, year: 2024, month: 4, day: 7).date ?? .now,
            note: "Our first night together in Singapore. We stayed up way too late talking about everything and nothing.",
            photoSeed: 1
        ),
        Memory(
            title: "Marina Bay Sands rooftop",
            emoji: "🌃",
            place: singapore,
            date: DateComponents(calendar: .current, year: 2024, month: 4, day: 8).date ?? .now,
            note: "The view from the rooftop bar was unreal. We stayed until the lights across the bay turned off one by one.",
            photoSeed: 2
        ),
        Memory(
            title: "Our favourite café",
            emoji: "☕️",
            place: singapore,
            date: DateComponents(calendar: .current, year: 2024, month: 4, day: 9).date ?? .now,
            note: "We came back to this café three days in a row. Now it's just \"our place\".",
            photoSeed: 3
        ),
        Memory(
            title: "The last coffee before the airport",
            emoji: "✈️",
            place: singapore,
            date: DateComponents(calendar: .current, year: 2024, month: 4, day: 10).date ?? .now,
            note: "Neither of us said much. We didn't need to.",
            photoSeed: 4
        ),
        Memory(
            title: "Weekend in Bangkok",
            emoji: "🛺",
            place: bangkok,
            date: DateComponents(calendar: .current, year: 2024, month: 3, day: 4).date ?? .now,
            note: "Street food, night markets, and way too many photos.",
            photoSeed: 5
        ),
    ]

    /// Headline relationship stats — matches the numbers used throughout the README.
    struct RelationshipStats {
        var totalDistanceKm: Double
        var tripCount: Int
        var flightCount: Int
        var countryCount: Int
        var daysTogether: Int
        var earthMultiple: Double
    }

    static let stats = RelationshipStats(
        totalDistanceKm: 84_392,
        tripCount: 9,
        flightCount: 14,
        countryCount: 4,
        daysTogether: 127,
        earthMultiple: 2.1
    )

    static let nextReunionDaysToGo = 47
}
