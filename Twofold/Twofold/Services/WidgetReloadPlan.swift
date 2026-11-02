//
//  WidgetReloadPlan.swift
//  Twofold
//
//  Which widget timelines to reload after the app writes a new snapshot. Main-app-only: the
//  widgets never reload themselves this way.
//

import Foundation
import WidgetKit

/// The images the app caches for the widgets in the app group (see `WidgetImageCache`). The
/// widgets read them at render time, so a new image only shows once its widgets reload.
enum WidgetImage: Hashable {
    case myAvatar
    case partnerAvatar
    case airlineLogo
    case latestMemory
}

/// WidgetKit gives each widget a daily budget of reloads, and a widget that has spent it keeps
/// showing whatever it last rendered. The app used to reload every widget at every snapshot write,
/// twice per write — and on a travel day the snapshot is rewritten every minute or two for hours
/// while the flight is tracked, which is exactly when the flight widgets matter most (FLT-23).
///
/// So a write reloads only the widgets whose inputs changed: the snapshot fields each one reads,
/// and the cached images it shows. Entries are cheap and reloads are not; the widgets' own
/// timelines carry them between writes (see `FlightWidgetTimeline`).
enum WidgetReloadPlan {
    /// The snapshot fields each widget's provider reads, by their coding keys. A field missing
    /// here goes stale on that widget until its own scheduled reload; a field no widget claims
    /// fails `WidgetReloadPlanTests`, so a new one has to be placed.
    static let inputs: [WidgetKind: Set<String>] = [
        .partnersTime: ["partnerName", "partnerCity", "partnerTimeZoneIdentifier"],
        .daysTogether: ["anniversaryDate", "myName", "partnerName"],
        .tripCountdown: ["nextReunion", "upcomingTrips"],
        .flightCountdown: ["nextFlight", "trackedFlights", "subscriptionTier", "myName", "partnerName"],
        .flightTracking: ["nextFlight", "trackedFlights", "subscriptionTier", "myName", "partnerName"],
        .timeWeather: ["subscriptionTier", "partnerCity", "partnerTimeZoneIdentifier", "partnerWeather"],
        .drawingPad: [
            "coupleID", "myID", "partnerID", "myName", "partnerName", "subscriptionTier",
            "mySignedDrawingPadURL", "partnerSignedDrawingPadURL",
        ],
        .smartRotating: [
            "subscriptionTier", "nextFlight", "dailyQuestion", "latestMemory", "anniversaryDate",
            "myName", "partnerName", "partnerSignedDrawingPadURL",
        ],
        .distance: ["distanceLabel", "isSameCity", "myCity", "partnerCity", "myName", "partnerName"],
        .distanceCompact: ["distanceLabel", "isSameCity", "myCity", "partnerCity", "myName", "partnerName"],
        .relationshipSummary: ["anniversaryDate", "myName", "partnerName", "relationshipStats", "upcomingTrips"],
        .dailyQuestion: ["dailyQuestion", "partnerName"],
        .memories: ["latestMemory"],
    ]

    /// Fields that change on every write and reload nothing. `writtenAt` is the age of the
    /// weather reading for Time & Weather, which only needs it on its own hourly reload: a write
    /// that brings no new reading doesn't make the old one any newer.
    static let ignored: Set<String> = ["writtenAt"]

    /// The widgets that show each cached image.
    static let imageReaders: [WidgetImage: Set<WidgetKind>] = [
        .myAvatar: avatarReaders,
        .partnerAvatar: avatarReaders,
        .airlineLogo: [.flightTracking],
        .latestMemory: [.memories, .smartRotating],
    ]

    private static let avatarReaders: Set<WidgetKind> = [
        .daysTogether, .partnersTime, .flightCountdown, .flightTracking, .smartRotating, .relationshipSummary,
    ]

    /// The kinds whose timelines should reload, going from `old` to `new` with `changedImages`
    /// rewritten, plus `forced`. Everything when there was no snapshot before, or when either
    /// can't be compared.
    static func kinds(
        from old: WidgetSnapshot?,
        to new: WidgetSnapshot,
        changedImages: Set<WidgetImage> = [],
        forced: Set<WidgetKind> = []
    ) -> Set<WidgetKind> {
        guard let old, let before = fields(of: old), let after = fields(of: new) else {
            return Set(WidgetKind.allCases)
        }
        let changed = Set(before.keys).union(after.keys).filter { key in
            !ignored.contains(key) && !isEqual(before[key], after[key])
        }
        var kinds = forced
        for (kind, reads) in inputs where !reads.isDisjoint(with: changed) {
            kinds.insert(kind)
        }
        for image in changedImages {
            kinds.formUnion(imageReaders[image] ?? [])
        }
        return kinds
    }

    /// The snapshot as JSON, less what changes without changing anything a widget shows:
    ///
    /// - A flight's stored `progress`, whenever it has both times. The tracking widget works the
    ///   rail out from those for each entry, and the stored figure moves on every refresh while
    ///   the flight is in the air.
    /// - The single `delaySeconds`, which is the departure or arrival delay below depending on
    ///   when it was written.
    /// - A drawing pad URL's signature. Every refresh signs the pads again, so the query string
    ///   is new every time while the pad it points at is the same; the widget re-reads the URL on
    ///   its own half-hourly reload, well inside the signature's twelve hours.
    private static func fields(of snapshot: WidgetSnapshot) -> [String: Any]? {
        var comparable = snapshot
        comparable.nextFlight = snapshot.nextFlight.map(comparableFlight)
        comparable.trackedFlights = snapshot.trackedFlights.map(comparableFlight)
        comparable.mySignedDrawingPadURL = snapshot.mySignedDrawingPadURL.map(withoutQuery)
        comparable.partnerSignedDrawingPadURL = snapshot.partnerSignedDrawingPadURL.map(withoutQuery)
        guard let data = try? JSONEncoder().encode(comparable) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func comparableFlight(_ flight: WidgetSnapshot.FlightInfo) -> WidgetSnapshot.FlightInfo {
        var flight = flight
        if let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure {
            flight.progress = 0
        }
        flight.delaySeconds = nil
        return flight
    }

    private static func withoutQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        return components.url ?? url
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return (lhs as AnyObject).isEqual(rhs)
        default: return false
        }
    }

    /// Hands `kinds` to WidgetKit, and nothing when there are none.
    static func reload(_ kinds: Set<WidgetKind>) {
        guard !kinds.isEmpty else { return }
        if kinds == Set(WidgetKind.allCases) {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }
}
