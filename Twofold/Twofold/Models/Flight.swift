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
    /// Resolved server-side against the `airports` reference table at flight-creation time (see
    /// add-flight/index.ts) — never provided by AeroAPI itself. Lets flight stats compute
    /// domestic/international/countries directly per flight, with no dependency on a linked Trip.
    var country: String?

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

    /// Whether there's anything here the flight card actually draws. Narrower than `isEmpty`,
    /// which asks whether the provider returned anything at all: wind speed is still stored (it
    /// comes free with the METAR observation) but no longer displayed, so a reading holding only
    /// a wind summary has nothing to show even though it isn't empty.
    var hasDisplayableReading: Bool { conditions != nil || temperatureC != nil }
}

/// Base `FlightStatus` enum lives in `Shared/FlightStatus.swift` (shared with
/// `LiveActivitiesExtension`) — `semanticColor` depends on `Theme`, which is main-app-only, so
/// it stays here as a separate extension instead.
extension FlightStatus {
    /// Status is never conveyed by color alone (`displayLabel`/icon always carry the meaning
    /// too) — this just tints existing Twofold semantic colors, never introduces new hues.
    var semanticColor: Color {
        switch self {
        case .delayed: Theme.warning
        case .cancelled, .diverted: Theme.error
        case .landed, .arrived: Theme.success
        case .scheduled, .boarding, .departed, .inAir, .landingSoon: Theme.accent
        }
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

/// `Codable` so `OfflineDataCache` can persist real travel data for offline reads — every
/// stored property here is already a value type Swift can synthesise conformance for
/// (`FlightAirport`/`FlightWeather`/`FlightStatus` are each `Codable` in their own right).
struct Flight: Identifiable, Hashable, Codable {
    let id: UUID
    /// Optional link to a Trip — a flight can exist and be tracked entirely on its own.
    var tripID: UUID?
    var coupleID: UUID?
    var createdBy: UUID?
    /// Who's actually on this flight — set explicitly when adding it (not inferred from a
    /// linked trip, since flights don't require one). Empty when left unspecified; can hold both
    /// partners when they're travelling together.
    var travelerIDs: [UUID]
    /// Set once resolved against AeroAPI; nil for a purely self-reported flight.
    var faFlightID: String?
    var flightNumberIATA: String
    /// The codeshare designator the traveller searched/booked under (e.g. "CX6104"), when it
    /// differs from the operating number in `flightNumberIATA` (e.g. "CA104"). Nil when they
    /// searched the operating number directly, which is the common case. Written once at
    /// add-flight time and never refreshed — see 20260912000200.
    var marketingFlightNumber: String?
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
        travelerIDs: [UUID] = [],
        faFlightID: String? = nil,
        flightNumberIATA: String,
        marketingFlightNumber: String? = nil,
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
        self.travelerIDs = travelerIDs
        self.faFlightID = faFlightID
        self.flightNumberIATA = flightNumberIATA
        self.marketingFlightNumber = marketingFlightNumber
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

    var flightNumber: String { marketingFlightNumber ?? flightNumberIATA }

    /// The stored value (from `airline_logo_url`, currently never populated server-side since
    /// AeroAPI doesn't supply one) if present, otherwise derived from the airline code — see
    /// `AirlineLogo`.
    var displayLogoURL: URL? { airlineLogoURL ?? AirlineLogo.url(forIATACode: airlineCode) }

    /// Airline code prefixed onto the number when AeroAPI hasn't already included it
    /// (self-reported flights are entered as a single free-text field, so this is a no-op
    /// for those — `flightNumberIATA` already reads e.g. "QF35").
    var displayNumber: String {
        // What the traveller booked under wins: CX6104 is on their boarding pass and the departure
        // board, CA104 is only who physically flies it. It already carries its own airline prefix,
        // so the code-prefixing below doesn't apply to it.
        if let marketingFlightNumber { return marketingFlightNumber }
        if let airlineCode, !flightNumberIATA.hasPrefix(airlineCode) { return "\(airlineCode)\(flightNumberIATA)" }
        return flightNumberIATA
    }

    /// Confirmed live: CI5175 had `actual_off` (wheels up) populated by AeroAPI but no
    /// `actual_out`/`estimated_out`/`scheduled_out` at all (a gate-pushback report gap, not
    /// uncommon for some airline/airport combinations) — falling back to the off/on milestones
    /// once the out/in family is entirely empty means `progress` (which guards on `bestDeparture
    /// == nil`) stops silently reporting 0% for a flight that's genuinely mid-air, and the map's
    /// progress-interpolated fallback marker (used whenever `positionCoordinate` has no live
    /// ADS-B fix) stops rendering frozen at the origin. `timeline` below already prefers
    /// `actualOff ?? actualOut` for exactly this reason — this mirrors that same convention.
    var bestDeparture: Date? { actualOut ?? estimatedOut ?? scheduledOut ?? actualOff ?? estimatedOff ?? scheduledOff }
    var bestArrival: Date? { actualIn ?? estimatedIn ?? scheduledIn ?? actualOn ?? estimatedOn ?? scheduledOn }

    /// Worth showing as current: under way, not yet departed, or landed within the last 15 minutes
    /// — long enough that a flight doesn't vanish out of "active/upcoming" (Home's carousel,
    /// `AppModel.activeOrUpcomingFlights`) the instant it lands, giving a moment to still see
    /// "Landed"/baggage info before it's archived into past flights.
    ///
    /// Not the same question as `isInProgress`, which is what a trip asks: a flight next month is
    /// currently relevant (it belongs in "upcoming") but is not in progress.
    var isCurrentlyRelevant: Bool { isCurrentlyRelevant(at: .now) }

    func isCurrentlyRelevant(at now: Date) -> Bool {
        if displayStatus(at: now).isActivelyTracked { return true }
        guard let arrival = bestArrival else { return false }
        return arrival.addingTimeInterval(15 * 60) > now
    }

    /// Actually under way: in the air or at the gate by the provider's word, or past its departure
    /// by the clock and not yet 15 minutes past its arrival. What `Trip.isActive` asks.
    ///
    /// `Trip.isActive` used to ask `isCurrentlyRelevant`, which is true for any flight that hasn't
    /// landed — so a reunion next month with its flight attached was "active" today, and Home said
    /// "You're together now" and drew the trip on the globe a month early (CORE-1).
    func isInProgress(at now: Date = .now) -> Bool {
        guard !cancelled else { return false }
        if displayStatus(at: now).isActivelyTracked { return true }
        guard let departure = bestDeparture, departure <= now, let arrival = bestArrival else { return false }
        return arrival.addingTimeInterval(15 * 60) > now
    }

    /// How long a tracked flight's stored status is taken at its word. The server re-checks a
    /// flight every few minutes around departure and while airborne, so a status older than this
    /// means the polling has stopped, not that nothing has happened.
    static let statusFreshness: TimeInterval = 60 * 60

    /// The status to show: the stored one while tracking is live and recent, otherwise moved along
    /// the clock with `FlightStatus.projected`.
    ///
    /// A flight nobody is tracking never hears from the provider again, so its stored status is
    /// whatever it was when it was saved. "Past flights" said "Departing shortly" ten days after it
    /// flew, and a flight whose tracking stopped mid-air stayed "En route" forever (FLT-8). The
    /// widget already projected; the app now does the same, with the same conservative rules.
    func displayStatus(at now: Date = .now) -> FlightStatus {
        if trackingEnabled, let refreshed = lastRefreshedAt, now.timeIntervalSince(refreshed) < Self.statusFreshness {
            return status
        }
        return status.projected(departure: bestDeparture, arrival: bestArrival, now: now)
    }

    /// Done: cancelled, diverted, landed, or past its arrival by the clock (its departure, when no
    /// arrival is known). The clock counts because an untracked flight stays `.scheduled` after it
    /// has flown — and the tracking screen offered to spend one of the month's live-tracked slots
    /// on it (FLT-10). `enable_flight_tracking` applies the same rule server-side (20261117000400).
    func isOver(at now: Date = .now) -> Bool {
        if status.isTerminal || cancelled || diverted { return true }
        guard let reference = bestArrival ?? bestDeparture else { return false }
        return reference <= now
    }

    /// This row, with any airport zone it lacks taken from `previous` — the same flight as the app
    /// already had it, zones resolved (`AppModel.resolveMissingAirportTimezones`).
    ///
    /// The tracking screen refetches its flight on open and on every realtime change, and the raw
    /// row has no zone for a schedule-only flight. Replacing the screen's copy with it moved every
    /// time on the screen into the home-zone fallback a second after opening (FLT-6). Only copied for
    /// the same airport, and never over a zone the row does carry.
    func keepingTimeZones(from previous: Flight) -> Flight {
        var merged = self
        if merged.origin.timezone == nil, merged.origin.iata == previous.origin.iata {
            merged.origin.timezone = previous.origin.timezone
        }
        if merged.destination.timezone == nil, merged.destination.iata == previous.destination.iata {
            merged.destination.timezone = previous.destination.timezone
        }
        return merged
    }

    /// Who is on this plane, decided once for every surface (FLT-14): the flight's own
    /// `travelerIDs` when set, else its linked trip's, else whoever added it.
    ///
    /// The Live Activity, the widget, the tracking screen's title, the map and the share sticker
    /// each used to work this out their own way, so an older flight with no travellers set read as
    /// "You're on the way" on the Lock Screen beside the partner's photo on the widget.
    /// `AppModel.travellerIDs(for:)` looks the trip up.
    func travellerIDs(linkedTrip: Trip?) -> [UUID] {
        if !travelerIDs.isEmpty { return travelerIDs }
        if let linkedTrip, !linkedTrip.travelerIDs.isEmpty { return linkedTrip.travelerIDs }
        return createdBy.map { [$0] } ?? []
    }

    /// The moment the countdown is about: the departure until the plane has left the gate, the
    /// arrival after. `countdownSummary` counts to it and the tracking screen's home-time line
    /// anchors it, so the two lines under the header always describe the same instant — they
    /// disagreed for a boarding flight, which counted to departure above the arrival time (FLT-7).
    func countdownMilestone(at now: Date = .now) -> Date? {
        switch displayStatus(at: now) {
        case .cancelled, .diverted: return nil
        case .scheduled, .delayed, .boarding: return bestDeparture
        case .departed, .inAir, .landingSoon, .landed, .arrived: return bestArrival
        }
    }

    /// Legacy convenience for call sites that only ever dealt in a single scheduled window.
    var scheduledDeparture: Date { scheduledOut ?? .now }
    var scheduledArrival: Date { scheduledIn ?? scheduledOut?.addingTimeInterval(3600 * 4) ?? .now }

    /// Past `FlightDelay`'s threshold at either end — the one every surface uses.
    var isDelayed: Bool {
        FlightDelay.isDelayed(seconds: departureDelaySeconds) || FlightDelay.isDelayed(seconds: arrivalDelaySeconds)
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

    /// Gate-to-gate duration, using the same best-known-time fallback chain as `progress` (actual
    /// times once flown, estimated/scheduled beforehand) — nil rather than a bogus value when
    /// either end isn't known yet.
    var totalDuration: TimeInterval? {
        guard let departure = bestDeparture, let arrival = bestArrival, arrival > departure else { return nil }
        return arrival.timeIntervalSince(departure)
    }

    /// "8h 1m" — the compact, unlabeled form used alongside the city→city route text, where the
    /// route itself already makes clear this is a flight duration.
    var totalDurationSummary: String? {
        guard let totalDuration else { return nil }
        let totalMinutes = Int(totalDuration / 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    /// Whether this flight actually happened — the gate for every travel statistic.
    ///
    /// Flight stats counted every row regardless of status, so a trip booked for next month made
    /// its destination an airport you had "visited", its carrier an airline you had flown, and its
    /// distance part of how far you'd travelled. A cancelled flight counted the same way, for a
    /// journey nobody took. Reported as stats that didn't add up: eighteen flights where sixteen
    /// had been flown, and airports neither partner had set foot in.
    ///
    /// Cancelled is excluded outright. Diverted is not — you flew, just not to the airport on the
    /// ticket. Everything else is decided by the clock rather than by status, because a flight
    /// that has landed isn't always *marked* landed: tracking stops when the provider stops
    /// reporting, and a flight added after the fact may never carry a live status at all.
    var hasBeenFlown: Bool {
        if cancelled { return false }
        switch status {
        case .cancelled:
            return false
        case .landed, .arrived, .diverted:
            // Diverted counts: you landed, just not where the ticket said.
            return true
        case .scheduled, .boarding, .delayed, .departed, .inAir, .landingSoon:
            // Still in progress as far as the provider knows — but tracking stops when the provider
            // stops reporting, and a flight added after the fact may never carry a live status at
            // all, so the clock decides rather than the status.
            break
        }
        // Arrival, not departure. A flight that has taken off hasn't necessarily got where it was
        // going — it can divert, turn back, or land somewhere else entirely — so it isn't a journey
        // taken until it's down. Departure is only the fallback for a flight with no arrival time
        // recorded at all.
        guard let reference = bestArrival ?? bestDeparture else { return false }
        return reference <= .now
    }

    var positionCoordinate: CLLocationCoordinate2D? {
        guard let positionLatitude, let positionLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: positionLatitude, longitude: positionLongitude)
    }

    /// Human "Departs in 2h 10m" / "Landing in 1h 33m" / "Arrived 18m ago" summary — the
    /// contextual line under the status badge everywhere this flight is shown.
    var countdownSummary: String { countdownSummary(at: .now) }

    /// How long ago a flight has to have finished before it reads as a date rather than a
    /// duration. "Arrived 30m ago" is a glance; "Arrived 10d 2h ago" is arithmetic.
    static let flewDateThreshold: TimeInterval = 6 * 60 * 60

    func countdownSummary(at now: Date) -> String {
        let status = displayStatus(at: now)
        switch status {
        case .cancelled: return "Cancelled"
        case .diverted: return "Diverted"
        case .arrived, .landed:
            if let arrival = bestArrival {
                if now.timeIntervalSince(arrival) > Self.flewDateThreshold, let flew = flewDate {
                    return "Flew \(flew)"
                }
                return "Arrived \(Self.relative(from: arrival, to: now)) ago"
            }
            if let flew = flewDate { return "Flew \(flew)" }
            return "Arrived"
        case .boarding:
            // Boarding means still at the gate, not yet departed — this was previously grouped
            // with the arrival-countdown cases below, which showed "Arrives in…" for a flight
            // that hadn't even taken off yet. Counts down to departure instead, same shape as
            // .scheduled/.delayed below.
            if let departure = bestDeparture, departure > now {
                return "Departs in \(Self.relative(from: now, to: departure))"
            }
            return status.emotionalHeadline
        case .landingSoon, .inAir, .departed:
            if let arrival = bestArrival, arrival > now {
                return "Arrives in \(Self.relative(from: now, to: arrival))"
            }
            return status.emotionalHeadline
        case .scheduled, .delayed:
            // Past its departure only while the provider still says so recently (see
            // `displayStatus`) — a stale one has been projected on by now.
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

    /// "11 Aug": the day it left, in the zone it left from — the date on the boarding pass, which
    /// across the date line is not the one the phone shows.
    private var flewDate: String? {
        guard let departure = bestDeparture else { return nil }
        return departure.formatted(Date.FormatStyle(timeZone: origin.timeZone ?? .current).day().month(.abbreviated))
    }

    private static func relative(from: Date, to: Date) -> String {
        TimeMath.compactDuration(to.timeIntervalSince(from))
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

/// 60-day on-time-performance stats for a flight's *designator* (e.g. "UAE1"), not this specific
/// tracked instance — fetched on demand via `AeroFlightService.fetchDelayStats`, computed and
/// cached server-side (see `supabase/functions/_shared/delay-stats.ts`). Field names match that
/// function's JSON response verbatim (camelCase both sides, same convention as every other
/// edge-function response this app decodes).
struct DelayStats: Decodable {
    var observedCount: Int
    var latePercent: Double
    var averageLateMinutes: Double
    var earlyPercent: Double
    var onTimePercent: Double
    var late15Percent: Double
    var late30Percent: Double
    var late45Percent: Double
    var cancelledPercent: Double
    var divertedPercent: Double
}
