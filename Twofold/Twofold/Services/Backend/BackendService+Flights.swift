//
//  BackendService+Flights.swift
//  Twofold
//
//  Flights, the live-tracking allowance, provider status events, per-flight notification
//  preferences, and their realtime channels.
//

import Foundation
import Supabase

extension BackendService {

    /// A couple's shared monthly flight allowance and how much of it is spent.
    nonisolated struct FlightAllowance: Decodable {
        var tier: String?
        var limit: Int
        var used: Int

        /// Never negative to show: two simultaneous adds can both pass the server's check, so
        /// `used` can legitimately come back above `limit` (see add-flight/index.ts).
        var remaining: Int { max(0, limit - used) }
    }

    /// Read straight from the database rather than through the edge function, so the Add Flight
    /// screen can say how many are left before anyone starts a search that is going to be
    /// refused. One RPC rather than a select because membership is checked inside
    /// `flight_allowance`, and the tier it reads lives in a schema PostgREST does not serve.
    static func flightAllowance(coupleID: UUID) async throws -> FlightAllowance {
        struct Params: Encodable {
            let pCoupleId: UUID
            enum CodingKeys: String, CodingKey {
                case pCoupleId = "p_couple_id"
            }
        }
        return try await supabase
            .rpc("flight_allowance", params: Params(pCoupleId: coupleID))
            .execute()
            .value
    }

    /// Why the server would not start tracking a flight.
    ///
    /// `enable_flight_tracking` has always reported a `reason` beside its `enabled: false`, and the
    /// client has always thrown it away and shown the allowance sentence for every refusal. That was
    /// true-by-accident while the allowance was the only reason it ever refused. Since
    /// 20261110001800 it also refuses a couple whose subscription has lapsed, and telling them their
    /// month's flights are used up is both wrong and unactionable — the allowance resets on the 1st
    /// and theirs never will.
    ///
    /// A reason this build does not recognise falls back to the allowance sentence, which is what
    /// every refusal used to say: a newer server adding a reason must not produce an empty message.
    enum FlightTrackingRefusal: String {
        case limitReached = "limit_reached"
        case subscriptionRequired = "subscription_required"
        case flightOver = "flight_over"

        var message: String {
            switch self {
            case .limitReached:
                "You've used all your live-tracked flights this month. Your allowance resets on the 1st."
            case .subscriptionRequired:
                "Live tracking needs an active subscription. Everything you've already saved stays exactly where it is."
            case .flightOver:
                "This flight has already arrived, so there's nothing left to follow."
            }
        }

        static func message(for reason: String?) -> String {
            guard let reason, let refusal = Self(rawValue: reason) else {
                return Self.limitReached.message
            }
            return refusal.message
        }
    }

    nonisolated struct FlightTrackingResult: Decodable {
        var enabled: Bool
        /// Only ever set when `enabled` is false. See `FlightTrackingRefusal`.
        var reason: String?
    }

    /// Spends one of the couple's monthly live-tracking slots on a flight that was saved without
    /// it — the flight a couple added after their allowance was gone.
    ///
    /// Not enabled when there is nothing to spend, when the couple's subscription has lapsed, or
    /// when the flight has already arrived and there would be nothing left to poll. The server
    /// decides all three: `enable_flight_tracking` is the only thing that may grant tracking, for
    /// the same reason the subscription columns are the webhook's alone — a client that could grant
    /// itself a slot has no allowance at all.
    static func enableFlightTracking(flightID: UUID) async throws -> FlightTrackingResult {
        struct Params: Encodable {
            let pFlightId: UUID
            enum CodingKeys: String, CodingKey {
                case pFlightId = "p_flight_id"
            }
        }
        return try await supabase
            .rpc("enable_flight_tracking", params: Params(pFlightId: flightID))
            .execute()
            .value
    }

    /// Flights are couple-scoped (not trip-scoped) — `tripId` is an optional link, not a
    /// join key. `status`/`progress`/`timeline` on the app-side `Flight` model are computed
    /// from these raw timestamps rather than duplicated here.
    struct FlightRow: Decodable {
        var id: UUID
        var tripId: UUID?
        var coupleId: UUID
        var createdBy: UUID?
        var travelerIds: [UUID]?
        var faFlightId: String?
        var flightNumberIata: String
        var marketingFlightNumber: String?
        var flightNumberIcao: String?
        var airlineName: String?
        var airlineCode: String?
        var airlineLogoUrl: String?
        var originIata: String?
        var originIcao: String?
        var originName: String?
        var originCity: String?
        var originTimezone: String?
        var originLatitude: Double?
        var originLongitude: Double?
        var originCountry: String?
        var destinationIata: String?
        var destinationIcao: String?
        var destinationName: String?
        var destinationCity: String?
        var destinationTimezone: String?
        var destinationLatitude: Double?
        var destinationLongitude: Double?
        var destinationCountry: String?
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
        var status: String
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

        enum CodingKeys: String, CodingKey {
            case id, cancelled, diverted, status, route, registration
            case tripId = "trip_id"
            case coupleId = "couple_id"
            case createdBy = "created_by"
            case travelerIds = "traveler_ids"
            case faFlightId = "fa_flight_id"
            case flightNumberIata = "flight_number_iata"
            case marketingFlightNumber = "marketing_flight_number"
            case flightNumberIcao = "flight_number_icao"
            case airlineName = "airline_name"
            case airlineCode = "airline_code"
            case airlineLogoUrl = "airline_logo_url"
            case originIata = "origin_iata"
            case originIcao = "origin_icao"
            case originName = "origin_name"
            case originCity = "origin_city"
            case originTimezone = "origin_timezone"
            case originLatitude = "origin_latitude"
            case originLongitude = "origin_longitude"
            case originCountry = "origin_country"
            case destinationIata = "destination_iata"
            case destinationIcao = "destination_icao"
            case destinationName = "destination_name"
            case destinationCity = "destination_city"
            case destinationTimezone = "destination_timezone"
            case destinationLatitude = "destination_latitude"
            case destinationLongitude = "destination_longitude"
            case destinationCountry = "destination_country"
            case aircraftType = "aircraft_type"
            case scheduledOut = "scheduled_out"
            case scheduledOff = "scheduled_off"
            case scheduledOn = "scheduled_on"
            case scheduledIn = "scheduled_in"
            case estimatedOut = "estimated_out"
            case estimatedOff = "estimated_off"
            case estimatedOn = "estimated_on"
            case estimatedIn = "estimated_in"
            case actualOut = "actual_out"
            case actualOff = "actual_off"
            case actualOn = "actual_on"
            case actualIn = "actual_in"
            case departureDelaySeconds = "departure_delay_seconds"
            case arrivalDelaySeconds = "arrival_delay_seconds"
            case terminalOrigin = "terminal_origin"
            case gateOrigin = "gate_origin"
            case terminalDestination = "terminal_destination"
            case gateDestination = "gate_destination"
            case baggageClaim = "baggage_claim"
            case positionLatitude = "position_latitude"
            case positionLongitude = "position_longitude"
            case positionAltitude = "position_altitude"
            case positionGroundspeed = "position_groundspeed"
            case positionHeading = "position_heading"
            case positionUpdatedAt = "position_updated_at"
            case weatherOrigin = "weather_origin"
            case weatherDestination = "weather_destination"
            case lastRefreshedAt = "last_refreshed_at"
            case trackingEnabled = "tracking_enabled"
        }
    }

    static func makeFlight(from row: FlightRow) -> Flight {
        Flight(
            id: row.id,
            tripID: row.tripId,
            coupleID: row.coupleId,
            createdBy: row.createdBy,
            travelerIDs: row.travelerIds ?? [],
            faFlightID: row.faFlightId,
            flightNumberIATA: row.flightNumberIata,
            marketingFlightNumber: row.marketingFlightNumber,
            flightNumberICAO: row.flightNumberIcao,
            airlineName: row.airlineName,
            airlineCode: row.airlineCode,
            airlineLogoURL: row.airlineLogoUrl.flatMap(URL.init(string:)),
            origin: FlightAirport(iata: row.originIata, icao: row.originIcao, name: row.originName, city: row.originCity, timezone: row.originTimezone, latitude: row.originLatitude, longitude: row.originLongitude, country: row.originCountry),
            destination: FlightAirport(iata: row.destinationIata, icao: row.destinationIcao, name: row.destinationName, city: row.destinationCity, timezone: row.destinationTimezone, latitude: row.destinationLatitude, longitude: row.destinationLongitude, country: row.destinationCountry),
            aircraftType: row.aircraftType,
            registration: row.registration,
            route: row.route,
            scheduledOut: row.scheduledOut,
            scheduledOff: row.scheduledOff,
            scheduledOn: row.scheduledOn,
            scheduledIn: row.scheduledIn,
            estimatedOut: row.estimatedOut,
            estimatedOff: row.estimatedOff,
            estimatedOn: row.estimatedOn,
            estimatedIn: row.estimatedIn,
            actualOut: row.actualOut,
            actualOff: row.actualOff,
            actualOn: row.actualOn,
            actualIn: row.actualIn,
            departureDelaySeconds: row.departureDelaySeconds,
            arrivalDelaySeconds: row.arrivalDelaySeconds,
            terminalOrigin: row.terminalOrigin,
            gateOrigin: row.gateOrigin,
            terminalDestination: row.terminalDestination,
            gateDestination: row.gateDestination,
            baggageClaim: row.baggageClaim,
            cancelled: row.cancelled,
            diverted: row.diverted,
            status: FlightStatus(rawValue: row.status) ?? .scheduled,
            positionLatitude: row.positionLatitude,
            positionLongitude: row.positionLongitude,
            positionAltitude: row.positionAltitude,
            positionGroundspeed: row.positionGroundspeed,
            positionHeading: row.positionHeading,
            positionUpdatedAt: row.positionUpdatedAt,
            weatherOrigin: row.weatherOrigin,
            weatherDestination: row.weatherDestination,
            lastRefreshedAt: row.lastRefreshedAt,
            trackingEnabled: row.trackingEnabled
        )
    }

    static func fetchFlights(coupleID: UUID) async throws -> [Flight] {
        let rows: [FlightRow] = try await supabase
            .from("flights")
            .select()
            .eq("couple_id", value: coupleID)
            .execute()
            .value
        return rows.map(Self.makeFlight)
    }

    static func fetchFlight(id: UUID) async throws -> Flight? {
        let rows: [FlightRow] = try await supabase
            .from("flights")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first.map(Self.makeFlight)
    }

    /// Stops tracking a flight entirely — status events, notification preferences, and
    /// documents all cascade-delete with it (see the flights_delete_members migration).
    static func deleteFlight(id: UUID) async throws {
        // Read before the delete, not after: `flight_documents` cascades with the flight, so once
        // it's gone the rows naming these paths are gone too and the files behind them can't be
        // found at all — orphaned *and* unreachable rather than merely orphaned.
        let documentPaths = await flightDocumentPaths(flightID: id)
        try await supabase
            .from("flights")
            .delete()
            .eq("id", value: id)
            .execute()
        await removeFlightDocumentObjects(documentPaths)
    }

    // MARK: - Flight status events (provider-sourced) & notification preferences

    private struct FlightStatusEventRow: Decodable {
        var id: UUID
        var flightId: UUID
        var type: FlightStatusEventType
        var previousValue: String?
        var newValue: String?
        var occurredAt: Date
        var source: String

        enum CodingKeys: String, CodingKey {
            case id, type, source
            case flightId = "flight_id"
            case previousValue = "previous_value"
            case newValue = "new_value"
            case occurredAt = "occurred_at"
        }

        func toModel() -> FlightStatusEvent {
            FlightStatusEvent(id: id, flightID: flightId, type: type, previousValue: previousValue, newValue: newValue, occurredAt: occurredAt, source: source)
        }
    }

    static func fetchFlightStatusEvents(flightID: UUID) async throws -> [FlightStatusEvent] {
        let rows: [FlightStatusEventRow] = try await supabase
            .from("flight_status_events")
            .select()
            .eq("flight_id", value: flightID)
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    /// A Realtime channel of newly-inserted provider events, written server-side by the
    /// AeroAPI sync pipeline.
    static func subscribeToFlightStatusEvents(flightID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<FlightStatusEvent>) {
        let channel = supabase.channel("flight_status_events_\(flightID.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            table: "flight_status_events",
            filter: .eq("flight_id", value: flightID.uuidString)
        )

        let (stream, continuation) = AsyncStream<FlightStatusEvent>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            for await insertion in insertions {
                guard let row = try? insertion.decodeRecord(as: FlightStatusEventRow.self, decoder: AnyJSON.decoder) else { continue }
                continuation.yield(row.toModel())
            }
            continuation.finish()
        }
        return (channel, stream)
    }

    /// Signal-only, same idea as `subscribeToGameSession` — the server-side 5-minute cron
    /// (`refresh-due-flights`) writes straight to this row, and without this the live-tracking
    /// screen had no way to learn about that except an initial load or an explicit pull-to-
    /// refresh, so it just sat stale between visits. The caller re-fetches via `fetchFlight`
    /// rather than trusting the realtime payload's shape.
    static func subscribeToFlightRefresh(flightID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        let channel = supabase.channel("flight_refresh_\(flightID.uuidString)")
        let updates = channel.postgresChange(UpdateAction.self, table: "flights", filter: .eq("id", value: flightID.uuidString))

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            for await _ in updates { continuation.yield(()) }
            continuation.finish()
        }
        return (channel, stream)
    }

    /// App-wide counterpart to `subscribeToFlightRefresh` — that one only covers a single flight
    /// while its detail screen happens to be open, which is exactly why a flight the server
    /// already archived (landed hours ago, `tracking_enabled` flipped false by
    /// `refresh-due-flights`'s cron) kept showing in Home/Trips until the user happened to open
    /// its detail screen: `AppModel.flights` had no way to learn about *any* server-side change
    /// while just sitting on a list screen. Scoped to the whole couple (every insert/update, not
    /// filtered to one row) and kept alive for as long as a couple is loaded, not just one view.
    static func subscribeToCoupleFlights(coupleID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        let channel = supabase.channel("couple_flights_\(coupleID.uuidString)")
        let inserts = channel.postgresChange(InsertAction.self, table: "flights", filter: .eq("couple_id", value: coupleID.uuidString))
        let updates = channel.postgresChange(UpdateAction.self, table: "flights", filter: .eq("couple_id", value: coupleID.uuidString))

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        Task {
            try? await channel.subscribeWithError()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in inserts { continuation.yield(()) } }
                group.addTask { for await _ in updates { continuation.yield(()) } }
            }
            continuation.finish()
        }
        return (channel, stream)
    }

    private struct NotificationPreferencesRow: Codable {
        var flightId: UUID
        var profileId: UUID
        var gateTerminalChanges: Bool
        var delayOrCancellation: Bool
        var departure: Bool
        var landing: Bool
        var arrivalAtGate: Bool
        var baggageClaimUpdate: Bool

        enum CodingKeys: String, CodingKey {
            case flightId = "flight_id"
            case profileId = "profile_id"
            case gateTerminalChanges = "gate_terminal_changes"
            case delayOrCancellation = "delay_or_cancellation"
            case departure, landing
            case arrivalAtGate = "arrival_at_gate"
            case baggageClaimUpdate = "baggage_claim_update"
        }

        func toModel() -> FlightNotificationPreferences {
            FlightNotificationPreferences(
                flightID: flightId, profileID: profileId,
                gateTerminalChanges: gateTerminalChanges, delayOrCancellation: delayOrCancellation,
                departure: departure, landing: landing,
                arrivalAtGate: arrivalAtGate, baggageClaimUpdate: baggageClaimUpdate
            )
        }
    }

    static func fetchNotificationPreferences(flightID: UUID) async throws -> FlightNotificationPreferences? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [NotificationPreferencesRow] = try await supabase
            .from("flight_notification_preferences")
            .select()
            .eq("flight_id", value: flightID)
            .eq("profile_id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first?.toModel()
    }

    static func upsertNotificationPreferences(_ prefs: FlightNotificationPreferences) async throws {
        try await supabase
            .from("flight_notification_preferences")
            .upsert(NotificationPreferencesRow(
                flightId: prefs.flightID, profileId: prefs.profileID,
                gateTerminalChanges: prefs.gateTerminalChanges, delayOrCancellation: prefs.delayOrCancellation,
                departure: prefs.departure, landing: prefs.landing,
                arrivalAtGate: prefs.arrivalAtGate, baggageClaimUpdate: prefs.baggageClaimUpdate
            ), onConflict: "flight_id,profile_id")
            .execute()
    }

    /// The only way to change `flights.trip_id` after a flight's already been added — every
    /// other write path (`AeroFlightService.addFlight`) only ever sets it once, at creation.
    /// Pass `nil` to unlink.
    static func setFlightTrip(flightID: UUID, tripID: UUID?) async throws {
        try await supabase
            .from("flights")
            .update(TripIDUpdate(tripId: tripID))
            .eq("id", value: flightID)
            .execute()
    }

    private struct FlightTravelerUpdate: Encodable {
        var travelerIds: [UUID]
        enum CodingKeys: String, CodingKey { case travelerIds = "traveler_ids" }
    }

    /// Same gap as `flight.tripID` used to be — travelers were only ever set once, at
    /// add-flight time, with no way to change them afterward. Pass an empty array to clear.
    /// Holds 0, 1, or 2 ids — both partners can be marked as travelling together on one flight.
    static func setFlightTravelers(flightID: UUID, travelerIDs: [UUID]) async throws {
        try await supabase
            .from("flights")
            .update(FlightTravelerUpdate(travelerIds: travelerIDs))
            .eq("id", value: flightID)
            .execute()
    }
}
