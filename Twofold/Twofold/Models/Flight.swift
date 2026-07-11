//
//  Flight.swift
//  Twofold
//
//  A flight can be a rich, AeroAPI-resolved record (real schedule/position/weather data,
//  synced server-side — see AeroFlightService) or a lightweight self-reported one (manual
//  entry during trip creation, no live tracking). Every field beyond the flight number and
//  the two airports is optional for exactly that reason — never fabricate a value the
//  provider hasn't actually supplied; render "Not available" instead (see FlightDetailView).
//

import CoreLocation
import SwiftUI

/// Denormalized airport snapshot as reported by the flight provider — distinct from `Place`,
/// which is the app's own curated, user-facing city list. A flight's airports may not (and in
/// general won't) appear in `Place.commonCities`.
struct FlightAirport: Hashable, Codable {
    var iata: String?
    var icao: String?
    var name: String?
    var city: String?
    var timezone: String?
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? { timezone.flatMap(TimeZone.init(identifier:)) }

    /// Short code for compact display ("MEL"), falling back gracefully when a provider
    /// hasn't supplied an IATA code.
    var displayCode: String { iata ?? icao ?? city ?? "—" }
    var displayName: String { city ?? name ?? displayCode }
}

struct FlightWeather: Hashable, Codable {
    var conditions: String?
    var temperatureC: Double?
    var windSummary: String?

    var isEmpty: Bool { conditions == nil && temperatureC == nil && windSummary == nil }
}

enum FlightStatus: String, Hashable, Codable, CaseIterable {
    case scheduled
    case boarding
    case departed
    case inAir = "in_air"
    case landingSoon = "landing_soon"
    case landed
    case arrived
    case delayed
    case cancelled
    case diverted

    var emotionalHeadline: String {
        switch self {
        case .scheduled: "Getting ready to fly ✈️"
        case .boarding: "Boarding now ✈️"
        case .departed: "They're on their way ✈️"
        case .inAir: "On the way to you ❤️"
        case .landingSoon: "Almost there ❤️"
        case .landed: "They've landed ❤️"
        case .arrived: "They've arrived safely ❤️"
        case .delayed: "Running a little late"
        case .cancelled: "Flight cancelled"
        case .diverted: "Flight diverted"
        }
    }

    /// Short badge label — deliberately distinct wording from `emotionalHeadline`, which is
    /// for the big header moment; this is for compact chips/cards.
    var displayLabel: String {
        switch self {
        case .scheduled: "Scheduled"
        case .boarding: "Boarding"
        case .departed: "Departed"
        case .inAir: "En route"
        case .landingSoon: "Landing soon"
        case .landed: "Landed"
        case .arrived: "Arrived"
        case .delayed: "Delayed"
        case .cancelled: "Cancelled"
        case .diverted: "Diverted"
        }
    }

    /// Status is never conveyed by color alone (`displayLabel`/icon always carry the meaning
    /// too) — this just tints existing Twofold semantic colors, never introduces new hues.
    var semanticColor: Color {
        switch self {
        case .delayed, .cancelled, .diverted: Theme.heartRed
        case .landed, .arrived: Theme.leafGreen
        case .scheduled, .boarding, .departed, .inAir, .landingSoon: Theme.skyBlue
        }
    }

    var icon: String {
        switch self {
        case .scheduled: "clock"
        case .boarding: "figure.walk.arrival"
        case .departed: "airplane.departure"
        case .inAir: "airplane"
        case .landingSoon: "airplane.arrival"
        case .landed, .arrived: "checkmark.circle.fill"
        case .delayed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        case .diverted: "arrow.triangle.branch"
        }
    }

    var isActivelyTracked: Bool {
        [.boarding, .departed, .inAir, .landingSoon].contains(self)
    }
}

struct FlightTimelineEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case departed = "Departed"
        case inAir = "In the air"
        case landingSoon = "Landing soon"
        case arrived = "Arriving"
    }

    let id: UUID
    var kind: Kind
    var time: Date
    var isComplete: Bool

    init(id: UUID = UUID(), kind: Kind, time: Date, isComplete: Bool) {
        self.id = id
        self.kind = kind
        self.time = time
        self.isComplete = isComplete
    }
}

struct Flight: Identifiable, Hashable {
    let id: UUID
    /// Optional link to a Trip — a flight can exist and be tracked entirely on its own.
    var tripID: UUID?
    var coupleID: UUID?
    var createdBy: UUID?
    /// Set once resolved against AeroAPI; nil for a purely self-reported flight.
    var faFlightID: String?
    var flightNumberIATA: String
    var flightNumberICAO: String?
    var airlineName: String?
    var airlineCode: String?
    var airlineLogoURL: URL?
    var origin: FlightAirport
    var destination: FlightAirport
    var aircraftType: String?
    var registration: String?
    var route: String?

    var scheduledOut: Date?
    var scheduledOff: Date?
    var scheduledOn: Date?
    var scheduledIn: Date?
    var estimatedOut: Date?
    var estimatedOff: Date?
    var estimatedOn: Date?
    var estimatedIn: Date?
    var actualOut: Date?
    var actualOff: Date?
    var actualOn: Date?
    var actualIn: Date?

    var departureDelaySeconds: Int?
    var arrivalDelaySeconds: Int?

    var terminalOrigin: String?
    var gateOrigin: String?
    var terminalDestination: String?
    var gateDestination: String?
    var baggageClaim: String?

    var cancelled: Bool
    var diverted: Bool
    var status: FlightStatus

    var positionLatitude: Double?
    var positionLongitude: Double?
    var positionAltitude: Double?
    var positionGroundspeed: Double?
    var positionHeading: Double?
    var positionUpdatedAt: Date?

    var weatherOrigin: FlightWeather?
    var weatherDestination: FlightWeather?

    var lastRefreshedAt: Date?
    var trackingEnabled: Bool

    init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        coupleID: UUID? = nil,
        createdBy: UUID? = nil,
        faFlightID: String? = nil,
        flightNumberIATA: String,
        flightNumberICAO: String? = nil,
        airlineName: String? = nil,
        airlineCode: String? = nil,
        airlineLogoURL: URL? = nil,
        origin: FlightAirport,
        destination: FlightAirport,
        aircraftType: String? = nil,
        registration: String? = nil,
        route: String? = nil,
        scheduledOut: Date? = nil,
        scheduledOff: Date? = nil,
        scheduledOn: Date? = nil,
        scheduledIn: Date? = nil,
        estimatedOut: Date? = nil,
        estimatedOff: Date? = nil,
        estimatedOn: Date? = nil,
        estimatedIn: Date? = nil,
        actualOut: Date? = nil,
        actualOff: Date? = nil,
        actualOn: Date? = nil,
        actualIn: Date? = nil,
        departureDelaySeconds: Int? = nil,
        arrivalDelaySeconds: Int? = nil,
        terminalOrigin: String? = nil,
        gateOrigin: String? = nil,
        terminalDestination: String? = nil,
        gateDestination: String? = nil,
        baggageClaim: String? = nil,
        cancelled: Bool = false,
        diverted: Bool = false,
        status: FlightStatus = .scheduled,
        positionLatitude: Double? = nil,
        positionLongitude: Double? = nil,
        positionAltitude: Double? = nil,
        positionGroundspeed: Double? = nil,
        positionHeading: Double? = nil,
        positionUpdatedAt: Date? = nil,
        weatherOrigin: FlightWeather? = nil,
        weatherDestination: FlightWeather? = nil,
        lastRefreshedAt: Date? = nil,
        trackingEnabled: Bool = true
    ) {
        self.id = id
        self.tripID = tripID
        self.coupleID = coupleID
        self.createdBy = createdBy
        self.faFlightID = faFlightID
        self.flightNumberIATA = flightNumberIATA
        self.flightNumberICAO = flightNumberICAO
        self.airlineName = airlineName
        self.airlineCode = airlineCode
        self.airlineLogoURL = airlineLogoURL
        self.origin = origin
        self.destination = destination
        self.aircraftType = aircraftType
        self.registration = registration
        self.route = route
        self.scheduledOut = scheduledOut
        self.scheduledOff = scheduledOff
        self.scheduledOn = scheduledOn
        self.scheduledIn = scheduledIn
        self.estimatedOut = estimatedOut
        self.estimatedOff = estimatedOff
        self.estimatedOn = estimatedOn
        self.estimatedIn = estimatedIn
        self.actualOut = actualOut
        self.actualOff = actualOff
        self.actualOn = actualOn
        self.actualIn = actualIn
        self.departureDelaySeconds = departureDelaySeconds
        self.arrivalDelaySeconds = arrivalDelaySeconds
        self.terminalOrigin = terminalOrigin
        self.gateOrigin = gateOrigin
        self.terminalDestination = terminalDestination
        self.gateDestination = gateDestination
        self.baggageClaim = baggageClaim
        self.cancelled = cancelled
        self.diverted = diverted
        self.status = status
        self.positionLatitude = positionLatitude
        self.positionLongitude = positionLongitude
        self.positionAltitude = positionAltitude
        self.positionGroundspeed = positionGroundspeed
        self.positionHeading = positionHeading
        self.positionUpdatedAt = positionUpdatedAt
        self.weatherOrigin = weatherOrigin
        self.weatherDestination = weatherDestination
        self.lastRefreshedAt = lastRefreshedAt
        self.trackingEnabled = trackingEnabled
    }

    /// Minimal self-reported flight — manual entry during trip creation or onboarding's
    /// first-flight step, with no AeroAPI resolution behind it. Everything beyond the number,
    /// airports, and schedule stays nil/"Not available" until (if ever) it gets tracked for
    /// real via Add Flight's search flow.
    init(selfReportedNumber flightNumber: String, origin: Place, destination: Place, scheduledDeparture: Date, scheduledArrival: Date) {
        self.init(
            flightNumberIATA: flightNumber,
            origin: FlightAirport(iata: origin.iataCode, name: nil, city: origin.city, timezone: origin.timeZoneIdentifier, latitude: origin.latitude, longitude: origin.longitude),
            destination: FlightAirport(iata: destination.iataCode, name: nil, city: destination.city, timezone: destination.timeZoneIdentifier, latitude: destination.latitude, longitude: destination.longitude),
            scheduledOut: scheduledDeparture,
            scheduledIn: scheduledArrival,
            status: .scheduled
        )
    }

    var flightNumber: String { flightNumberIATA }

    /// Airline code prefixed onto the number when AeroAPI hasn't already included it
    /// (self-reported flights are entered as a single free-text field, so this is a no-op
    /// for those — `flightNumberIATA` already reads e.g. "QF35").
    var displayNumber: String {
        if let airlineCode, !flightNumberIATA.hasPrefix(airlineCode) { return "\(airlineCode)\(flightNumberIATA)" }
        return flightNumberIATA
    }

    var bestDeparture: Date? { actualOut ?? estimatedOut ?? scheduledOut }
    var bestArrival: Date? { actualIn ?? estimatedIn ?? scheduledIn }

    /// Legacy convenience for call sites that only ever dealt in a single scheduled window.
    var scheduledDeparture: Date { scheduledOut ?? .now }
    var scheduledArrival: Date { scheduledIn ?? scheduledOut?.addingTimeInterval(3600 * 4) ?? .now }

    var isDelayed: Bool {
        (departureDelaySeconds ?? 0) > 300 || (arrivalDelaySeconds ?? 0) > 300
    }

    /// 0...1 progress along the route, for placing the aircraft on the map/progress rail.
    var progress: Double {
        guard let departure = bestDeparture, let arrival = bestArrival, arrival > departure else {
            return status == .arrived || status == .landed ? 1 : 0
        }
        let elapsed = Date.now.timeIntervalSince(departure)
        let total = arrival.timeIntervalSince(departure)
        return min(1, max(0, elapsed / total))
    }

    var timeRemaining: TimeInterval {
        max(0, (bestArrival ?? .now).timeIntervalSinceNow)
    }

    var hasLivePosition: Bool { positionLatitude != nil && positionLongitude != nil }

    var positionCoordinate: CLLocationCoordinate2D? {
        guard let positionLatitude, let positionLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: positionLatitude, longitude: positionLongitude)
    }

    /// Human "Departs in 2h 10m" / "Landing in 1h 33m" / "Arrived 18m ago" summary — the
    /// contextual line under the status badge everywhere this flight is shown.
    var countdownSummary: String {
        let now = Date.now
        switch status {
        case .cancelled: return "Cancelled"
        case .diverted: return "Diverted"
        case .arrived, .landed:
            if let arrival = bestArrival {
                return "Arrived \(Self.relative(from: arrival, to: now)) ago"
            }
            return "Arrived"
        case .landingSoon, .inAir, .departed, .boarding:
            if let arrival = bestArrival, arrival > now {
                return "Arrives in \(Self.relative(from: now, to: arrival))"
            }
            return status.emotionalHeadline
        case .scheduled, .delayed:
            if let departure = bestDeparture {
                if departure > now {
                    return "Departs in \(Self.relative(from: now, to: departure))"
                } else {
                    return "Departing shortly"
                }
            }
            return status.displayLabel
        }
    }

    private static func relative(from: Date, to: Date) -> String {
        let totalSeconds = max(0, Int(to.timeIntervalSince(from)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Derived from actual/estimated timestamps rather than stored — there's nothing to keep
    /// in sync, it just reflects whatever the flight's current data says.
    var timeline: [FlightTimelineEvent] {
        var events: [FlightTimelineEvent] = []

        if let departed = actualOff ?? actualOut {
            events.append(FlightTimelineEvent(kind: .departed, time: departed, isComplete: true))
            events.append(FlightTimelineEvent(kind: .inAir, time: departed, isComplete: actualOn != nil || status == .landingSoon || status == .arrived || status == .landed))
        } else if let scheduled = scheduledOut {
            events.append(FlightTimelineEvent(kind: .departed, time: scheduled, isComplete: false))
        }

        if let arrival = bestArrival {
            events.append(FlightTimelineEvent(kind: .landingSoon, time: arrival.addingTimeInterval(-1800), isComplete: actualOn != nil || actualIn != nil))
            events.append(FlightTimelineEvent(kind: .arrived, time: arrival, isComplete: actualIn != nil))
        }

        return events
    }
}
