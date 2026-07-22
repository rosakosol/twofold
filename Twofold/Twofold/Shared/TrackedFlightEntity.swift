//
//  TrackedFlightEntity.swift
//  Twofold
//
//  Backs the Flight Countdown widget's "Edit Widget" flight picker (`SelectFlightIntent`) — this
//  app's first use of App Intents-based widget configuration. Same "extension reads only from
//  the shared App Group snapshot, never the network" rule every other widget already follows
//  (see WidgetSnapshotWriter.swift's header comment): the query below reads
//  `WidgetSnapshot.trackedFlights`, never Supabase/AppModel directly.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import AppIntents
import Foundation

struct TrackedFlightEntity: AppEntity {
    let id: UUID
    var flightNumber: String
    var originCode: String
    var destinationCode: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Flight"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(flightNumber)", subtitle: "\(originCode) → \(destinationCode)")
    }

    static var defaultQuery = TrackedFlightQuery()

    init(id: UUID, flightNumber: String, originCode: String, destinationCode: String) {
        self.id = id
        self.flightNumber = flightNumber
        self.originCode = originCode
        self.destinationCode = destinationCode
    }

    init(_ info: WidgetSnapshot.FlightInfo) {
        self.init(id: info.id, flightNumber: info.flightNumber, originCode: info.originCode, destinationCode: info.destinationCode)
    }
}

struct TrackedFlightQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TrackedFlightEntity] {
        let flights = WidgetSnapshot.read()?.trackedFlights ?? []
        return flights.filter { identifiers.contains($0.id) }.map(TrackedFlightEntity.init)
    }

    /// Populates the "Edit Widget" picker's option list — every flight the couple currently has
    /// tracked, soonest first (the order `WidgetSnapshotWriter` already sorts them in).
    func suggestedEntities() async throws -> [TrackedFlightEntity] {
        let flights = WidgetSnapshot.read()?.trackedFlights ?? []
        return flights.map(TrackedFlightEntity.init)
    }
}

struct SelectFlightIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Flight"
    static var description = IntentDescription("Pick which flight this widget counts down to. Leave unset to always show the soonest one.")

    // No explicit `query:` argument — resolved automatically via `TrackedFlightEntity.defaultQuery`.
    @Parameter(title: "Flight")
    var flight: TrackedFlightEntity?
}
