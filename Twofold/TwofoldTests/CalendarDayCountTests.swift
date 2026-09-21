//
//  CalendarDayCountTests.swift
//  TwofoldTests
//
//  "Today!", said on the 21st, about a trip on the 22nd.
//
//  Every day-count in the app measured how many 24-hour spans fit between two instants, which is
//  not what "how many days until" means to anybody. A trip leaving tomorrow morning is less than
//  24 hours away for most of today, so it counted as zero days and every screen that mentions it
//  — the trips list, the trips carousel, Home, the countdown widget, the Stats card's "Next
//  Reunion" — said the reunion was today.
//
//  The mirror of it sat on the anniversary: a relationship started on an evening six years ago
//  was, on the morning of the anniversary, eleven months and thirty-one days old by the same
//  arithmetic. The card read "5 years, 11 months" on the one day of the year it most needed to
//  say six.
//
//  These pin the boundary cases, in a fixed timezone so they do not pass or fail depending on
//  where the machine running them happens to be.
//

import Testing
import Foundation
@testable import Twofold

struct CalendarDayCountTests {
    /// Melbourne: a positive UTC offset, so a naive UTC-midnight reading lands on the right day
    /// here and the wrong one in the Americas. Both are exercised below.
    private var melbourne: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        calendar.locale = Locale(identifier: "en_AU")
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    // MARK: - The reported bug

    @Test("a trip tomorrow morning is one day away, asked about this afternoon")
    func tripTomorrowIsOneDay() {
        let calendar = melbourne
        // The exact case reported: today the 21st, trip on the 22nd. Nineteen hours apart, which
        // the old arithmetic called zero.
        let now = date(calendar, 2026, 9, 21, 13, 28)
        let departure = date(calendar, 2026, 9, 22, 8, 0)

        #expect(TimeMath.daysUntil(departure, now: now, calendar: calendar) == 1)
    }

    @Test("a trip later today is zero days away")
    func tripLaterTodayIsZero() {
        let calendar = melbourne
        let now = date(calendar, 2026, 9, 21, 6, 0)
        #expect(TimeMath.daysUntil(date(calendar, 2026, 9, 21, 23, 0), now: now, calendar: calendar) == 0)
    }

    @Test("one minute across midnight is a whole day")
    func acrossMidnightIsADay() {
        let calendar = melbourne
        // 23:59 to 00:00 is one minute of clock time and one day of calendar, which is the whole
        // distinction this helper exists to make.
        let now = date(calendar, 2026, 9, 21, 23, 59)
        #expect(TimeMath.daysUntil(date(calendar, 2026, 9, 22, 0, 0), now: now, calendar: calendar) == 1)
    }

    @Test("almost 24 hours inside one day is still zero")
    func withinOneDayIsZero() {
        let calendar = melbourne
        let now = date(calendar, 2026, 9, 21, 0, 1)
        #expect(TimeMath.daysUntil(date(calendar, 2026, 9, 21, 23, 59), now: now, calendar: calendar) == 0)
    }

    // MARK: - Direction

    @Test("a departure already past counts negative, so callers can clamp it")
    func pastDepartureIsNegative() {
        let calendar = melbourne
        let now = date(calendar, 2026, 9, 21, 13, 0)
        #expect(TimeMath.daysUntil(date(calendar, 2026, 9, 19, 8, 0), now: now, calendar: calendar) == -2)
        // Every caller wraps this in max(0, ...); the helper itself stays honest about direction.
        #expect(max(0, TimeMath.daysUntil(date(calendar, 2026, 9, 19, 8, 0), now: now, calendar: calendar)) == 0)
    }

    @Test("days since counts the other way")
    func daysSinceCountsBackwards() {
        let calendar = melbourne
        let now = date(calendar, 2026, 9, 21, 9, 0)
        // Started last night; it is a new day, so one day together.
        #expect(TimeMath.daysSince(date(calendar, 2026, 9, 20, 20, 0), now: now, calendar: calendar) == 1)
        // Started this morning, later than it is now — still the same day, so zero, not minus one.
        #expect(TimeMath.daysSince(date(calendar, 2026, 9, 21, 23, 0), now: now, calendar: calendar) == 0)
    }

    // MARK: - Timezone

    @Test("the day is the user's local day, not UTC's")
    func usesTheLocalDay() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        // 2026-09-22T02:00Z is still the evening of the 21st in New York. A trip "on the 22nd" by
        // UTC is today by the calendar the person is actually living in, and today is what they
        // should be told.
        let departure = Date(timeIntervalSince1970: 1_790_042_400)  // 2026-09-22T02:00:00Z
        let now = newYork.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9))!

        #expect(TimeMath.daysUntil(departure, now: now, calendar: newYork) == 0)
    }

    @Test("a DST boundary does not add or lose a day")
    func survivesDaylightSaving() {
        let calendar = melbourne
        // Melbourne moves to daylight time on 2026-10-04, so this span contains a 23-hour day.
        // Counting 24-hour spans would lose one; counting calendar days does not.
        let start = date(calendar, 2026, 10, 3, 12, 0)
        let end = date(calendar, 2026, 10, 5, 12, 0)
        #expect(TimeMath.calendarDaysBetween(start, end, calendar: calendar) == 2)
    }

    // MARK: - The anniversary

    @Test("an anniversary reads its full year on the morning of the day")
    func anniversaryIsWholeOnTheDay() {
        let calendar = melbourne
        let startedDatingOn = date(calendar, 2020, 9, 21, 20, 30)
        let now = date(calendar, 2026, 9, 21, 9, 0)

        let ymd = calendar.dateComponents(
            [.year, .month],
            from: calendar.startOfDay(for: startedDatingOn),
            to: calendar.startOfDay(for: now)
        )

        #expect(ymd.year == 6)
        #expect(ymd.month == 0)
    }
}
