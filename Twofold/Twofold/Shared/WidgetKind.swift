//
//  WidgetKind.swift
//  Twofold
//
//  Every Home Screen widget's `kind`, in one place: the widgets declare themselves with these, and
//  the app names them when it asks WidgetKit to reload only the ones whose data changed
//  (`WidgetReloadPlan`). Two copies of the strings could drift apart, and a reload for a kind that
//  no longer exists fails silently.
//
//  The raw values are what placed widgets are stored under. Changing one orphans every instance
//  of that widget on every Home Screen, which is why some no longer match their widget's name.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for that
//  target in project.pbxproj).
//

import Foundation

nonisolated enum WidgetKind: String, CaseIterable, Hashable {
    case partnersTime = "PartnersTimeWidget"
    case daysTogether = "DaysTogetherWidget"
    /// The trip countdown, under the name it shipped with.
    case tripCountdown = "NextReunionWidget"
    case flightCountdown = "FlightCountdownWidget"
    case flightTracking = "FlightTrackingWidget"
    case timeWeather = "TimeWeatherWidget"
    /// The drawing pad, under the name it shipped with.
    case drawingPad = "DoodlePadWidget"
    case smartRotating = "SmartRotatingWidget"
    case distance = "DistanceWidget"
    case distanceCompact = "DistanceCompactWidget"
    case relationshipSummary = "RelationshipSummaryWidget"
    case dailyQuestion = "DailyQuestionWidget"
    case memories = "MemoriesWidget"
}
