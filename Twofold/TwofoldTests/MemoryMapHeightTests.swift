//
//  MemoryMapHeightTests.swift
//  TwofoldTests
//
//  The Add Memory screen's map gives up its height as the form scrolls. The arithmetic is trivial;
//  the clamping isn't optional — unclamped, the height would keep changing past the point the map
//  can shrink, and rubber-banding at the top would stretch it past full size.
//
//  The map is layered over a fixed-frame scroll view rather than stacked above it, so nothing here
//  feeds back into the offset it reads. That was the earlier arrangement, and the juddering it
//  caused was reported as glitchy scrolling.
//

import Testing
import Foundation
@testable import Twofold

struct MemoryMapHeightTests {

    private let screen: CGFloat = 800
    private var expanded: CGFloat { screen * MemoryMapHeight.expandedFraction }
    private var collapsed: CGFloat { screen * MemoryMapHeight.collapsedFraction }

    private func height(_ offset: CGFloat) -> CGFloat {
        MemoryMapHeight.forOffset(offset, availableHeight: screen)
    }

    @Test("unscrolled, the map takes half the screen")
    func startsExpanded() {
        #expect(height(0) == expanded)
    }

    @Test("scrolling gives the map's height to the form, point for point")
    func shrinksWithTheScroll() {
        #expect(height(100) == expanded - 100)
        #expect(height(200) == expanded - 200)
    }

    @Test("the map stops shrinking once it's collapsed")
    func clampsAtTheBottom() {
        #expect(height(expanded - collapsed) == collapsed)
        #expect(height(10_000) == collapsed)
    }

    /// Rubber-banding at the top reports a negative offset, which must not stretch the map past
    /// half the screen.
    @Test("overscrolling upwards doesn't grow the map")
    func clampsAtTheTop() {
        #expect(height(-50) == expanded)
        #expect(height(-10_000) == expanded)
    }

    /// The property that matters: scrolling further never gives height back.
    @Test("height never increases as the scroll goes further")
    func isMonotonic() {
        var previous = CGFloat.greatestFiniteMagnitude
        for offset in stride(from: CGFloat(-100), through: 600, by: 10) {
            let current = height(offset)
            #expect(current <= previous, "height grew going from a smaller offset to \(offset)")
            previous = current
        }
    }

    /// The height is a function of the scroll offset and nothing else. Focusing the note field used
    /// to collapse the map directly; it scrolls the field up instead, and the height follows from
    /// that like any other scroll — which is what keeps the map and the content moving together.
    @Test("the height depends on the scroll offset alone")
    func dependsOnlyOnOffset() {
        #expect(height(120) == height(120))
        #expect(height(120) != height(0))
    }

    @Test("the map always keeps enough height to show the pin")
    func neverDisappears() {
        for offset in stride(from: CGFloat(0), through: 2000, by: 50) {
            #expect(height(offset) >= collapsed)
        }
    }
}
