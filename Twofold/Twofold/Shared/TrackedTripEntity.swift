//
//  TrackedTripEntity.swift
//  Twofold
//
//  Backs the Trip Countdown widget's "Edit Widget" trip picker (`SelectTripIntent`), mirroring
//  `TrackedFlightEntity` exactly — see that file for the pattern. Same rule as every other widget:
//  the query reads only the shared App Group snapshot (`WidgetSnapshot.upcomingTrips`), never
//  Supabase or AppModel directly.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import AppIntents
import Foundation

struct TrackedTripEntity: AppEntity {
    let id: UUID
    var destinationCity: String
    var departureDate: Date

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(destinationCity)",
            subtitle: "\(departureDate.formatted(date: .abbreviated, time: .omitted))"
        )
    }

    static var defaultQuery = TrackedTripQuery()

    init(id: UUID, destinationCity: String, departureDate: Date) {
        self.id = id
        self.destinationCity = destinationCity
        self.departureDate = departureDate
    }

    /// Nil for a trip the snapshot has no id for — one written before `ReunionInfo` carried one.
    /// Such a trip simply doesn't appear in the picker until the next snapshot write, which is
    /// better than offering an option that can't be selected back.
    init?(_ info: WidgetSnapshot.ReunionInfo) {
        guard let id = info.id else { return nil }
        self.init(id: id, destinationCity: info.destinationCity, departureDate: info.departureDate)
    }
}

struct TrackedTripQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TrackedTripEntity] {
        upcoming().filter { identifiers.contains($0.id) }
    }

    /// Populates the "Edit Widget" picker — every upcoming trip the couple has, soonest first
    /// (the order `AppModel.upcomingTrips` already sorts them in, preserved by the writer).
    func suggestedEntities() async throws -> [TrackedTripEntity] {
        upcoming()
    }

    private func upcoming() -> [TrackedTripEntity] {
        (WidgetSnapshot.read()?.upcomingTrips ?? []).compactMap(TrackedTripEntity.init)
    }
}

struct SelectTripIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Trip"
    static var description = IntentDescription("Pick which trip this widget counts down to. Leave unset to always show the soonest one.")

    // No explicit `query:` argument — resolved automatically via `TrackedTripEntity.defaultQuery`.
    @Parameter(title: "Trip")
    var trip: TrackedTripEntity?
}
