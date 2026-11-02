//
//  FlightLocalTime.swift
//  Twofold
//
//  Flight times in the airport's own zone, for the surfaces that live outside the app.
//
//  The tracking screen shows every time in that airport's local time, because that is what the
//  boarding pass and the departure board say: UA60 leaves San Francisco at 11:20pm. The Lock
//  Screen, the Dynamic Island and the flight tracking widget used `Text(_, style: .time)` and
//  `Calendar.current`, so on a phone in Melbourne the same departure read 4:20pm — and "travel day"
//  was the phone's day, not San Francisco's (FLT-5).
//
//  The app writes the zone to use into the Live Activity's attributes and the widget snapshot:
//  the airport's own, or the viewer's home zone where the airport's isn't known — the tracking
//  screen's fallback, decided app-side once. This only renders what it is given; the phone's own
//  zone is the last resort for a card or snapshot written before the zones existed.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for that
//  target in project.pbxproj).
//

import Foundation

nonisolated enum FlightLocalTime {
    /// The zone named, or the phone's when there isn't one (or it isn't a zone at all).
    static func timeZone(_ identifier: String?) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// "11:20 PM", in that zone.
    static func timeStyle(_ identifier: String?, locale: Locale = .autoupdatingCurrent) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone(identifier))
    }

    /// Whether two instants fall on the same calendar day in that zone.
    static func isSameDay(_ lhs: Date, _ rhs: Date, timeZoneID: String?) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(timeZoneID)
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
