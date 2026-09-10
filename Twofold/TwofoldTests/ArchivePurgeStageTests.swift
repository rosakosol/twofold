//
//  ArchivePurgeStageTests.swift
//  TwofoldTests
//
//  Which of four states the archive screen's destructive half is in, and — the part that actually
//  matters — whether that tap destroys anything.
//
//  This screen used to have one button that wiped a shared archive for both people on one person's
//  say-so. It now has a request that needs both, and a per-person hide that destroys nothing. The
//  risk in that design is a confirmation dialog that says "this can't be undone" for a tap that
//  only sends a request: say it when it isn't true and people learn to skip it, and then it's
//  worthless on the one tap where it is true.
//

import Testing
import Foundation
@testable import Twofold

struct ArchivePurgeStageTests {

    private func state(
        hidden: Bool = false,
        mine: Bool = false,
        theirs: Bool = false,
        partnerExists: Bool = true
    ) -> BackendService.CoupleArchiveState {
        .init(hidden: hidden, iRequestedPurge: mine, partnerRequestedPurge: theirs, partnerExists: partnerExists)
    }

    @Test("nobody has asked")
    func nobodyAsked() {
        #expect(ArchivePurgeStage.resolve(state()) == .nobodyAsked)
        // A lookup that failed must not read as "the partner is gone", which is the one state
        // that would let a single tap destroy everything.
        #expect(ArchivePurgeStage.resolve(nil) == .nobodyAsked)
    }

    @Test("I asked and I'm waiting")
    func awaitingPartner() {
        #expect(ArchivePurgeStage.resolve(state(mine: true)) == .awaitingPartner)
    }

    @Test("my partner asked and it's on me")
    func partnerAsked() {
        #expect(ArchivePurgeStage.resolve(state(theirs: true)) == .partnerAsked)
    }

    /// Both having asked is unreachable: the second request purges, the couple row goes, and the
    /// preference rows cascade with it. So this only happens if something else is already wrong —
    /// which is exactly why it resolves to the harmless side.
    ///
    /// `.partnerAsked` would put a button on screen that deletes on the next tap. `.awaitingPartner`
    /// offers "cancel my request" and destroys nothing. Between two readings of a state that should
    /// not exist, the one that cannot delete anything is the right answer. (This assertion began
    /// life the other way round and failed; the code was right and the test was wrong.)
    @Test("both asked resolves to the side that cannot delete")
    func bothAsked() {
        let stage = ArchivePurgeStage.resolve(state(mine: true, theirs: true))
        #expect(stage == .awaitingPartner)
        #expect(stage.deletesImmediately == false)
    }

    /// With the partner gone, what they did or didn't ask for before leaving decides nothing.
    @Test("a departed partner leaves one owner, whatever they had asked for")
    func soleOwner() {
        #expect(ArchivePurgeStage.resolve(state(partnerExists: false)) == .soleOwner)
        #expect(ArchivePurgeStage.resolve(state(mine: true, partnerExists: false)) == .soleOwner)
        #expect(ArchivePurgeStage.resolve(state(theirs: true, partnerExists: false)) == .soleOwner)
    }

    // MARK: - The one that matters

    /// Two of the four destroy nothing on this tap. If either ever claims otherwise, the warning
    /// on the two that do stops being believed.
    @Test("only the two states that really delete say so")
    func onlyRealDeletionsWarn() {
        #expect(ArchivePurgeStage.nobodyAsked.deletesImmediately == false)
        #expect(ArchivePurgeStage.awaitingPartner.deletesImmediately == false)
        #expect(ArchivePurgeStage.partnerAsked.deletesImmediately == true)
        #expect(ArchivePurgeStage.soleOwner.deletesImmediately == true)
    }

    /// Hiding is orthogonal to all of it — it is one person's view, and it must never change what
    /// the delete button is about to do.
    @Test("hiding does not change what deleting means")
    func hidingIsOrthogonal() {
        #expect(ArchivePurgeStage.resolve(state(hidden: true)) == .nobodyAsked)
        #expect(ArchivePurgeStage.resolve(state(hidden: true, theirs: true)) == .partnerAsked)
    }

    /// `partnerIsWaitingOnMe` is what separates "they asked" from "we both asked" — and it must not
    /// read as true just because I haven't asked.
    @Test("partnerIsWaitingOnMe needs an actual request from them")
    func partnerIsWaitingNeedsTheirRequest() {
        #expect(state(theirs: true).partnerIsWaitingOnMe)
        #expect(!state().partnerIsWaitingOnMe)
        #expect(!state(mine: true, theirs: true).partnerIsWaitingOnMe)
    }
}
