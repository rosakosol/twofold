//
//  CountdownMomentsTests.swift
//  TwofoldTests
//
//  The flight-tracking widget shows "55m" as a plain string worked out per timeline entry, so the
//  entries decide whether it is ever right. `TimeMath.countdownMoments` puts them on the target's
//  own minute marks: every minute in the last hour, every five before that, within a horizon.
//

import Testing
import Foundation
@testable import Twofold

struct CountdownMomentsTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("every entry in the last hour shows a whole number of minutes, one minute apart")
    func lastHourIsMinuteByMinute() {
        // Not on a minute boundary from `now`, which is the case that drifts if entries are
        // spaced from now rather than from the target.
        let arrival = now.addingTimeInterval(55 * 60 + 23)
        let moments = TimeMath.countdownMoments(to: [arrival], from: now)

        let labels = moments.map { TimeMath.compactDuration(arrival.timeIntervalSince($0)) }
        #expect(labels.first == "55m", "the entry for now")
        // After now: 55m, 54m … 1m, then 0m at touchdown — each minute exactly once.
        #expect(Array(labels.dropFirst()) == (0...55).reversed().map { "\($0)m" })
        for moment in moments.dropFirst() {
            #expect(arrival.timeIntervalSince(moment).truncatingRemainder(dividingBy: 60) == 0)
        }
    }

    @Test("further out than an hour, entries are five minutes apart on the target's marks")
    func beforeTheLastHourEveryFiveMinutes() {
        let departure = now.addingTimeInterval(2 * 3600 + 30)
        let moments = TimeMath.countdownMoments(to: [departure], from: now)
        let minutesBefore = moments.dropFirst().map { Int(departure.timeIntervalSince($0) / 60) }

        #expect(minutesBefore.filter { $0 > 60 } == [120, 115, 110, 105, 100, 95, 90, 85, 80, 75, 70, 65])
        #expect(minutesBefore.filter { $0 <= 60 }.count == 61)
    }

    @Test("nothing past the horizon, however far away the target is")
    func horizonBoundsTheTimeline() {
        let tenHours = now.addingTimeInterval(10 * 3600)
        let moments = TimeMath.countdownMoments(to: [tenHours], from: now, horizon: 3 * 3600)
        #expect(moments.allSatisfy { $0 <= now.addingTimeInterval(3 * 3600) })
        // Five-minute marks only, that far out.
        #expect(moments.dropFirst().allSatisfy { Int(tenHours.timeIntervalSince($0) / 60) % 5 == 0 })
    }

    @Test("both take-off and touchdown get their entries, and a past target none")
    func departureAndArrival() {
        let departed = now.addingTimeInterval(-3600)
        let departure = now.addingTimeInterval(10 * 60)
        let arrival = now.addingTimeInterval(70 * 60)
        let moments = TimeMath.countdownMoments(to: [departed, departure, arrival], from: now)

        #expect(moments.contains(departure))
        #expect(moments.contains(arrival))
        #expect(moments.allSatisfy { $0 >= now })
        #expect(moments == moments.sorted())
        #expect(Set(moments).count == moments.count)
    }

    @Test("no targets is just now")
    func noTargets() {
        #expect(TimeMath.countdownMoments(to: [], from: now) == [now])
    }

    @Test("a clock gets now, then every minute boundary for the next hour")
    func clockMinuteMarks() {
        let midMinute = now.addingTimeInterval(23)
        let marks = TimeMath.minuteMarks(from: midMinute, minutes: 60, calendar: Calendar(identifier: .gregorian))

        #expect(marks.first == midMinute)
        #expect(marks.count == 61)
        for mark in marks.dropFirst() {
            #expect(mark > midMinute)
            #expect(mark.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
        }
        #expect(marks.last!.timeIntervalSince(midMinute) <= 3600)
    }
}
