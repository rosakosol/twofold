//
//  UnsetAnniversaryTests.swift
//  TwofoldTests
//
//  "Together for 0 days."
//
//  A couple who never gave an anniversary had one anyway: today. `Couple.startedDatingOn` was not
//  optional, so the placeholder couple, and any couple whose `started_dating_on` was null, was
//  dated to `.now`. The Stats card then said "0 days", the widgets counted up from the day the
//  snapshot was written, and Partner setup's date picker showed today as the anniversary. The
//  anniversary can be skipped now, so this is the ordinary case, not a corner.
//

import Foundation
import Testing
@testable import Twofold

@Suite("An anniversary nobody has given is not today")
@MainActor
struct UnsetAnniversaryTests {

    @Test("Stats has no time-together figure for a couple with no anniversary")
    func statsHaveNoTimeTogether() {
        let stats = RelationshipMilestoneStats(couple: CoupleSession.placeholderCouple, trips: [], memories: [])

        #expect(stats.daysTogether == nil, "an unset anniversary counted as zero days together")
        #expect(stats.timeTogetherLabel == nil, "an unset anniversary was labelled as a length of time")
    }

    @Test("a given anniversary still counts")
    func givenAnniversaryCounts() {
        var couple = CoupleSession.placeholderCouple
        couple.startedDatingOn = Date(timeIntervalSinceNow: -10 * 86_400)
        let stats = RelationshipMilestoneStats(couple: couple, trips: [], memories: [])

        #expect(stats.daysTogether == 10)
        #expect(stats.timeTogetherLabel == "10 days")
    }

    @Test("the widgets are not told the relationship started today")
    func widgetSnapshotHasNoAnniversary() async {
        let model = AppModel()
        model.session.partnerConnected = true
        model.session.couple = CoupleSession.placeholderCouple
        let written = WrittenSnapshots()

        let refresh = Task {
            await WidgetSnapshotWriter.refresh(appModel: model, write: { written.items.append($0) }, reload: { _ in })
        }
        for _ in 0..<500 where written.items.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // Only the first, local write matters here; the rest is network work this stops.
        model.resetAccountScopedState()
        refresh.cancel()

        #expect(!written.items.isEmpty, "precondition: the local half is written straight away")
        #expect(written.items.first?.anniversaryDate == nil, "the widgets were handed today as the anniversary")
    }
}
