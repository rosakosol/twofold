//
//  ArchiveDeletionCountdownTests.swift
//  TwofoldTests
//
//  The countdown on an archived relationship.
//
//  This number is the only warning anyone gets before a shared history is permanently deleted, and
//  the deletion happens whether or not either person agrees to it. So the direction of the rounding
//  matters more than the arithmetic: "3 days left" has to mean at least three. Rounding the other
//  way tells someone they have until Thursday and deletes on Wednesday.
//

import Testing
import Foundation
@testable import Twofold

struct ArchiveDeletionCountdownTests {

    /// A future deadline gets a minute added to it, so no test sits on an exact day boundary.
    ///
    /// `Date(timeIntervalSinceNow: 44 days)` has already lost microseconds by the time the value is
    /// read back, so it floors to 43 — the flooring working, not failing. Testing on a boundary
    /// measures the clock instead. This bit twice: once in `floorsRatherThanRounds`, which I
    /// patched by hand, and then again here in a test I had left alone, which had been passing on
    /// luck. Putting the margin in the helper fixes the class rather than the instance.
    ///
    /// Past deadlines are passed straight through — those are meant to be in the past.
    private func archive(purgeIn seconds: TimeInterval?) -> ArchivedCouple {
        let stamp = seconds.map { Date(timeIntervalSinceNow: $0 > 0 ? $0 + 60 : $0) }
        return ArchivedCouple(
            id: UUID(),
            partnerName: "Alex",
            startedDatingOn: nil,
            dissolvedAt: nil,
            scheduledPurgeAt: stamp
        )
    }

    private static let day: TimeInterval = 86_400

    /// Floored, never rounded. 3.9 days is "3 days left", because someone acting on that number
    /// on day three must still find their data there.
    ///
    /// The helper's margin keeps these off exact boundaries; see its comment.
    @Test("the countdown floors rather than rounds")
    func floorsRatherThanRounds() {
        #expect(archive(purgeIn: Self.day * 3.9).daysUntilDeletion == 3)
        #expect(archive(purgeIn: Self.day * 3.1).daysUntilDeletion == 3)
        #expect(archive(purgeIn: Self.day * 90).daysUntilDeletion == 90)
    }

    /// Under a day is "today", not "0 days" and never a negative. Deletion runs from a nightly
    /// job, so a stamp already in the past just means it goes on the next run.
    @Test("a passed deadline reads as today, not as a negative")
    func passedDeadlineReadsAsToday() {
        #expect(archive(purgeIn: -Self.day * 5).daysUntilDeletion == 0)
        #expect(archive(purgeIn: -Self.day * 5).deletionNotice == "Deletes today")
        #expect(archive(purgeIn: Self.day * 0.5).deletionNotice == "Deletes today")
    }

    @Test("the wording is singular where it should be")
    func wording() {
        #expect(archive(purgeIn: Self.day * 1.2).deletionNotice == "Deletes tomorrow")
        #expect(archive(purgeIn: Self.day * 44).deletionNotice == "Deletes in 44 days")
    }

    /// A live relationship has no deadline, and must not render one. `daysUntilDeletion` returning
    /// 0 here would put "Deletes today" on a couple who are perfectly together.
    @Test("no deadline shows nothing at all")
    func noDeadlineShowsNothing() {
        #expect(archive(purgeIn: nil).daysUntilDeletion == nil)
        #expect(archive(purgeIn: nil).deletionNotice == nil)
        #expect(archive(purgeIn: nil).deletionIsImminent == false, "a couple with no deadline is never urgent")
    }

    /// The red/grey threshold. Two weeks is about the last point at which someone could still
    /// notice, decide, and get their data out.
    @Test("urgency turns on a fortnight out")
    func urgencyThreshold() {
        #expect(archive(purgeIn: Self.day * 20).deletionIsImminent == false)
        #expect(archive(purgeIn: Self.day * 14.5).deletionIsImminent == true)
        #expect(archive(purgeIn: Self.day * 1).deletionIsImminent == true)
        #expect(archive(purgeIn: -Self.day).deletionIsImminent == true)
    }
}
