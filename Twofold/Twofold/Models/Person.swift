//
//  Person.swift
//  Twofold
//

import SwiftUI

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Unset until the person completes the "where are you based?" onboarding step,
    /// or for a partner who hasn't set theirs yet.
    var homeCity: Place?
    var accentColor: Color
    /// Public URL for their uploaded profile photo. Nil falls back to the initials avatar.
    var avatarURL: URL?
    /// Their birthday, month and day, with no year — see migration 20261110001300 for why the
    /// year is not collected. Nil when they have not given one, which is always allowed.
    ///
    /// Carried on `Person` rather than on the couple because each side owns their own: it is read
    /// from whichever profile row this person is, so my partner's birthday is the one *they*
    /// entered rather than my guess at it. That is the opposite of `partner_name`, which is
    /// deliberately private and per-viewer.
    var birthday: Birthday?
    /// Where they are, as an IANA identifier — written on every foreground by
    /// `BackendService.updateDeviceContext`. Nil for anyone who has not opened the app since it
    /// started being recorded.
    var timeZoneIdentifier: String?

    init(id: UUID = UUID(), name: String, homeCity: Place? = nil, accentColor: Color, avatarURL: URL? = nil, birthday: Birthday? = nil, timeZoneIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.homeCity = homeCity
        self.accentColor = accentColor
        self.avatarURL = avatarURL
        self.birthday = birthday
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Whether it is their birthday **where they are**, not where whoever is looking happens to be.
    ///
    /// The distinction is the whole product. Melbourne and London are eleven hours apart, so a
    /// viewer's-local reading tells somebody in London it is their partner's birthday once London
    /// reaches the date — by which point the partner in Melbourne is most of a day into it. Turn
    /// the pair around and it fires most of a day early instead. Either way the one moment this
    /// screen exists for is missed, in an app built entirely around people not sharing a clock.
    ///
    /// Falls back to the viewer's calendar when their timezone is unknown, which is the best
    /// available answer rather than a good one: it is what the old behaviour did for everybody.
    var isBirthdayToday: Bool { isBirthday(at: .now) }

    /// The instant is a parameter so this can be tested at a chosen moment rather than whenever the
    /// suite happens to run — the whole behaviour is about which calendar date a given instant
    /// falls on in a given zone, and a test that cannot choose the instant cannot check it.
    func isBirthday(at instant: Date) -> Bool {
        guard let birthday else { return false }
        var calendar = Calendar.current
        if let identifier = timeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year else { return false }
        let observed = birthday.observed(inYear: year)
        return parts.month == observed.month && parts.day == observed.day
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return String(letters).uppercased()
    }
}


/// A birthday without a year.
///
/// Its own type rather than two loose integers on `Person`, so "month" and "day" cannot be passed
/// in the wrong order — the one mistake a pair of `Int`s invites and the compiler cannot catch.
struct Birthday: Hashable, Codable {
    let month: Int
    let day: Int

    /// Nil unless both halves are present and in range, which is also how the database states it
    /// (`profiles_birthday_range`: both null, or both set). Nothing downstream has to handle a
    /// half-set birthday because one cannot be built.
    init?(month: Int?, day: Int?) {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.month = month
        self.day = day
    }

    /// For the date picker, which deals in `Date`. The year is arbitrary and never stored — a leap
    /// year so 29 February survives the round trip.
    init?(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.month, .day], from: date)
        self.init(month: parts.month, day: parts.day)
    }

    func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day))
    }

    /// Which day this birthday is actually marked on in a given year.
    ///
    /// Only ever differs for 29 February, which does not exist in a common year. The choice there
    /// is the 28th or the 1st; this takes the 28th, keeping the day inside the month the birthday
    /// belongs to. `private.birthday_occurrence` (migration 20261110001500) makes the identical
    /// substitution, because the reminder push and this screen disagreeing about which day it is
    /// would be worse than either answer on its own.
    func observed(inYear year: Int) -> (month: Int, day: Int) {
        guard month == 2, day == 29, !Self.isLeapYear(year) else { return (month, day) }
        return (2, 28)
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// "14 March" — no year, because there is not one.
    var displayText: String {
        guard let date = date() else { return "" }
        return date.formatted(.dateTime.day().month(.wide))
    }
}
