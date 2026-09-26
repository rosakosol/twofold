//
//  BirthdayTests.swift
//  TwofoldTests
//
//  Whether it is somebody's birthday, judged where that somebody actually is.
//
//  This is the one piece of the feature with a wrong answer that looks right. `isBirthdayToday`
//  originally used `Calendar.current` — the *viewer's* calendar — which is correct only for two
//  people sharing a timezone, and this app is for two people who do not. Melbourne and London sit
//  eleven hours apart: reading the date locally tells somebody in London it is their partner's
//  birthday once London reaches it, by which point Melbourne is most of a day in; reverse the pair
//  and it fires most of a day early. Both misses are silent, and both land on the single day the
//  screen exists for.
//
//  So these pin the timezone, not the date arithmetic.
//

import Testing
import Foundation
@testable import Twofold

struct BirthdayTests {

    private func person(birthday: Birthday?, zone: String?) -> Person {
        Person(
            name: "Alex",
            accentColor: Person.palette[0],
            birthday: birthday,
            timeZoneIdentifier: zone
        )
    }

    /// A moment chosen so the calendar date genuinely differs across the two zones: 13 March
    /// 22:00 UTC is already 14 March in Melbourne (+11) and still 13 March in London.
    private var theMomentTheDatesDisagree: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 13
        components.hour = 22
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: components)!
    }

    @Test("a birthday is judged in its owner's timezone, not the viewer's")
    func ownersTimezoneDecides() {
        // Same instant, same birthday, two people. The Melbourne one is having their birthday; the
        // London one is not yet. A viewer-local reading would give both the same answer, which is
        // the bug this guards.
        let melbourne = person(birthday: Birthday(month: 3, day: 14), zone: "Australia/Melbourne")
        let london = person(birthday: Birthday(month: 3, day: 14), zone: "Europe/London")

        // Expressed against a fixed instant rather than `.now`, so the test does not depend on
        // when it runs.
        #expect(melbourne.isBirthday(at: theMomentTheDatesDisagree) == true)
        #expect(london.isBirthday(at: theMomentTheDatesDisagree) == false)
    }

    @Test("an unknown timezone falls back rather than refusing to celebrate")
    func unknownTimezoneFallsBack() {
        // Nil is the normal state for anyone who has not opened the app since `updateDeviceContext`
        // started recording it, so this branch is real. Falling back to the viewer's calendar is
        // the old behaviour — imperfect, and better than never showing the screen.
        let todayHere = Calendar.current.dateComponents([.month, .day], from: .now)
        let matching = person(birthday: Birthday(month: todayHere.month!, day: todayHere.day!), zone: nil)

        #expect(matching.isBirthdayToday == true)
    }

    @Test("no birthday is never a birthday")
    func noBirthdayNeverFires() {
        #expect(person(birthday: nil, zone: "Australia/Melbourne").isBirthdayToday == false)
    }

    @Test("a birthday needs both halves and sane ranges")
    func birthdayRejectsNonsense() {
        // Mirrors `profiles_birthday_range`, so the client cannot build a value the database would
        // refuse. Day 29-31 stay valid: without a year there is no way to reject 31 February that
        // does not also reject a leap-day birthday.
        #expect(Birthday(month: 3, day: nil) == nil)
        #expect(Birthday(month: nil, day: 14) == nil)
        #expect(Birthday(month: 13, day: 1) == nil)
        #expect(Birthday(month: 0, day: 1) == nil)
        #expect(Birthday(month: 3, day: 32) == nil)
        #expect(Birthday(month: 2, day: 29) != nil)
    }

    @Test("a birthday survives the round trip through a Date")
    func roundTripsThroughDate() {
        // The pickers deal in `Date`; the storage does not. A leap-day birthday is the one that
        // breaks if the year used in between is not itself a leap year.
        let leapDay = Birthday(month: 2, day: 29)
        #expect(leapDay != nil)
        let asDate = leapDay?.date()
        #expect(asDate != nil)
        #expect(asDate.flatMap { Birthday(date: $0) } == leapDay)
    }

    @Test("a leap-day birthday is marked on 28 February in a common year")
    func leapDayFallsBackToTheTwentyEighth() {
        let leapDay = Birthday(month: 2, day: 29)!

        // A leap year keeps the real date.
        #expect(leapDay.observed(inYear: 2028) == (month: 2, day: 29))
        // A common year moves to the 28th, not to 1 March — and `private.birthday_occurrence`
        // makes the same choice, so the reminder push and the celebration screen agree.
        #expect(leapDay.observed(inYear: 2027) == (month: 2, day: 28))
        // Centuries are the case a naive "divisible by four" gets wrong: 1900 was not a leap year,
        // 2000 was.
        #expect(leapDay.observed(inYear: 1900) == (month: 2, day: 28))
        #expect(leapDay.observed(inYear: 2000) == (month: 2, day: 29))
    }

    @Test("an ordinary birthday is never moved")
    func ordinaryBirthdaysAreUntouched() {
        // The substitution must be reachable only by 29 February. A 28 February birthday in a leap
        // year stays on the 28th rather than being dragged along with it.
        #expect(Birthday(month: 2, day: 28)!.observed(inYear: 2028) == (month: 2, day: 28))
        #expect(Birthday(month: 3, day: 1)!.observed(inYear: 2027) == (month: 3, day: 1))
    }

}
