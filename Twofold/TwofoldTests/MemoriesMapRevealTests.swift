//
//  MemoriesMapRevealTests.swift
//  TwofoldTests
//
//  The pin reveal's timing, which used to be a flat beat per pin and so made "how long until the
//  map is finished drawing" a straight multiple of how many places a couple had been to. Forty
//  places meant 4.8 seconds of half-empty map — the couples with the most to show waited longest.
//
//  Two properties matter and pull against each other: the effect has to be unchanged for the
//  ordinary case, and it has to be bounded for the large one. Both are pinned here.
//

import Testing
@testable import Twofold

struct MemoriesMapRevealTests {

    /// The delay applied to the last pin in a set of `count` — the point the map is finished.
    private func lastPinDelay(count: Int) -> Double {
        MemoriesMapView.pinRevealStagger(count: count) * Double(count - 1)
    }

    @Test("a small map keeps exactly the beat it always had")
    func smallMapUnchanged() {
        // Ten pins finish inside the window, so nothing should compress: this is the case where
        // a regression would be invisible in a big-N test but obvious on screen.
        #expect(MemoriesMapView.pinRevealStagger(count: 10) == 0.12)
        #expect(MemoriesMapView.pinRevealStagger(count: 4) == 0.12)
        #expect(MemoriesMapView.pinRevealStagger(count: 2) == 0.12)
    }

    @Test("a big map still finishes revealing quickly")
    func bigMapIsBounded() {
        // The regression this exists for: at a flat 0.12 this was 4.68s.
        #expect(lastPinDelay(count: 40) <= MemoriesMapView.pinRevealWindow)
        #expect(lastPinDelay(count: 200) <= MemoriesMapView.pinRevealWindow)
    }

    @Test("no set of pins takes longer than the window, at any size")
    func everySizeIsBounded() {
        for count in 1...300 {
            #expect(
                lastPinDelay(count: count) <= MemoriesMapView.pinRevealWindow + 0.0001,
                "\(count) pins ran over the window"
            )
        }
    }

    /// Degenerate counts. A stagger for one pin is multiplied by zero either way, but a negative
    /// or NaN delay handed to `withAnimation` is a different class of problem, and `count - 1` is
    /// a division by zero waiting to happen.
    @Test("one pin, or none, produces a usable delay")
    func degenerateCounts() {
        #expect(MemoriesMapView.pinRevealStagger(count: 1) == 0)
        #expect(MemoriesMapView.pinRevealStagger(count: 0) == 0)
    }

    /// Pins reveal in order — the effect is a sweep, and a stagger that ever went negative would
    /// run it backwards.
    @Test("the stagger is never negative")
    func neverNegative() {
        for count in 0...300 {
            #expect(MemoriesMapView.pinRevealStagger(count: count) >= 0)
        }
    }
}
