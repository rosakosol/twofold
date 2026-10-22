//
//  FlightStickerData.swift
//  Twofold
//
//  Everything the six flight stickers show (SHARE_REDESIGN.md §5), worked out once from the flight
//  so the sticker views only lay it out. Times are local to the airport they belong to; distances
//  follow the user's unit setting.
//

import CoreLocation
import SwiftUI

/// Where the flight is, which decides which stickers lead (§4).
enum FlightMoment {
    case beforeDeparture, inAir, landed

    init(_ status: FlightStatus) {
        switch status {
        case .departed, .inAir, .landingSoon: self = .inAir
        case .landed, .arrived: self = .landed
        case .scheduled, .boarding, .delayed, .cancelled, .diverted: self = .beforeDeparture
        }
    }

    var hint: String {
        switch self {
        case .beforeDeparture: String(localized: "Before take-off")
        case .inAir: String(localized: "In the air")
        case .landed: String(localized: "Landed")
        }
    }
}

enum FlightStickerKind: String, CaseIterable, Identifiable {
    case boardingPass = "Boarding pass"
    case luggageTag = "Luggage tag"
    case live = "Live flight"
    case distance = "Distance"
    case arrivals = "Arrivals"
    case stamp = "Passport stamp"

    var id: Self { self }

    /// The chips in order for this moment; the first is preselected. Live flight only while
    /// the flight is in the air.
    static func ordered(for moment: FlightMoment) -> [FlightStickerKind] {
        let lead: [FlightStickerKind] = switch moment {
        case .beforeDeparture: [.boardingPass, .luggageTag, .distance]
        case .inAir: [.live, .distance]
        case .landed: [.arrivals, .stamp, .distance]
        }
        let rest = allCases.filter { !lead.contains($0) && ($0 != .live || moment == .inAir) }
        return lead + rest
    }
}

struct FlightStickerData {
    struct Airport {
        let code: String
        let city: String
        /// The country's flag as an emoji, or nil when the country isn't known.
        let flag: String?
        let country: String?
    }

    let flightNumber: String
    let origin: Airport
    let destination: Airport
    let moment: FlightMoment
    /// "22 Sep", "8:25 pm": local to the origin.
    let departureDate: String?
    let departureTime: String?
    /// Local to the destination.
    let arrivalDate: String?
    let arrivalTime: String?
    let arrivalYear: String?
    /// "9h 55m".
    let duration: String?
    /// "8,179 km" or "5,082 mi", or nil without both airports' positions.
    let distance: String?
    let terminal: String?
    /// 0...1.
    let progress: Double
    /// "2h 15m".
    let timeRemaining: String
    let remainingForVoiceOver: String
    /// Whose photo is on the Live flight sticker.
    let traveller: Person
    let travellerIsMe: Bool
    /// The arrivals board's pill.
    let arrivalStatus: ArrivalStatus

    enum ArrivalStatus: Equatable {
        case landed, onTime
        case delayed(minutes: Int)
    }

    init(flight: Flight, me: Person, partner: Person) {
        flightNumber = flight.displayNumber
        origin = Self.airport(flight.origin)
        destination = Self.airport(flight.destination)
        moment = FlightMoment(flight.status)

        let originZone = flight.origin.timeZone ?? .current
        let destinationZone = flight.destination.timeZone ?? .current
        departureDate = flight.bestDeparture.map { Self.dayMonth($0, originZone) }
        departureTime = flight.bestDeparture.map { Self.time($0, originZone) }
        arrivalDate = flight.bestArrival.map { Self.dayMonth($0, destinationZone) }
        arrivalTime = flight.bestArrival.map { Self.time($0, destinationZone) }
        arrivalYear = flight.bestArrival.map {
            var style = Date.FormatStyle().year()
            style.timeZone = destinationZone
            return $0.formatted(style)
        }

        duration = flight.totalDurationSummary
        if let from = flight.origin.coordinate, let to = flight.destination.coordinate {
            distance = MeasurementPreference.distanceLabel(km: Geo.distanceKm(from, to))
        } else {
            distance = nil
        }
        terminal = flight.terminalOrigin.flatMap { $0.isEmpty ? nil : $0 }
        progress = flight.progress

        let minutes = Int(flight.timeRemaining / 60)
        timeRemaining = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        remainingForVoiceOver = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))

        travellerIsMe = flight.travelerIDs.contains(me.id)
        traveller = travellerIsMe && !flight.travelerIDs.contains(partner.id) ? me : partner

        if moment == .landed {
            arrivalStatus = .landed
        } else if let delay = flight.arrivalDelaySeconds, delay >= 15 * 60 {
            arrivalStatus = .delayed(minutes: delay / 60)
        } else {
            arrivalStatus = .onTime
        }
    }

    // MARK: - Formatting

    private static func dayMonth(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle().day().month(.abbreviated)
        style.timeZone = zone
        return date.formatted(style)
    }

    private static func time(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    private static func airport(_ airport: FlightAirport) -> Airport {
        let region = airport.country.flatMap(regionCode(for:))
        return Airport(
            code: airport.displayCode,
            city: airport.displayName,
            flag: region.flatMap(flag(for:)),
            country: region.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? airport.country
        )
    }

    /// The airport table holds either an ISO code or an English country name; both resolve here.
    nonisolated static func regionCode(for country: String) -> String? {
        let trimmed = country.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 2 { return trimmed.uppercased() }
        let english = Locale(identifier: "en_US")
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 }
            .first { english.localizedString(forRegionCode: $0)?.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// Two regional indicator symbols, which every platform draws as the flag.
    nonisolated static func flag(for regionCode: String) -> String? {
        let scalars = regionCode.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }
}

extension FlightStickerData {
    /// QF80, Tokyo to Melbourne: the design's sample, for previews.
    static var sample: FlightStickerData {
        var flight = MockData.activeFlight
        flight.marketingFlightNumber = "QF80"
        flight.origin = FlightAirport(iata: "NRT", name: nil, city: "Tokyo", timezone: "Asia/Tokyo", latitude: 35.772, longitude: 140.3929, country: "Japan")
        flight.destination = FlightAirport(iata: "MEL", name: nil, city: "Melbourne", timezone: "Australia/Melbourne", latitude: -37.6690, longitude: 144.8410, country: "Australia")
        flight.terminalOrigin = "2"
        return FlightStickerData(flight: flight, me: MockData.dara, partner: MockData.rosa)
    }
}
