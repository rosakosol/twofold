//
//  ArchivedDataLoadTests.swift
//  TwofoldTests
//
//  The archive list after a load (UX-3).
//
//  A failed fetch used to come back as an empty list, so the screen said "No archived data" to
//  someone whose network had dropped, which reads as "your shared history is gone" to exactly the
//  person most likely to be worried about it: someone who has just removed a partner.
//

import Foundation
import Testing
@testable import Twofold

struct ArchivedDataLoadTests {

    private func couple(_ name: String) -> ArchivedCouple {
        ArchivedCouple(id: UUID(), partnerName: name, startedDatingOn: nil, dissolvedAt: nil, scheduledPurgeAt: nil)
    }

    @Test("a failed fetch is a failure, not an empty archive")
    func failureIsNotEmpty() async {
        let result = await ArchivedDataLoadResult.load { throw URLError(.notConnectedToInternet) }
        guard case .failed(let message) = result else {
            Issue.record("A failed fetch came back as \(result), which the screen shows as \"No archived data\"")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("an empty answer is an empty archive")
    func emptyIsEmpty() async {
        #expect(await ArchivedDataLoadResult.load { [] } == .loaded([]))
    }

    @Test("archives come through as they were fetched")
    func archivesComeThrough() async {
        let archives = [couple("Alex"), couple("Jo")]
        #expect(await ArchivedDataLoadResult.load { archives } == .loaded(archives))
    }
}
