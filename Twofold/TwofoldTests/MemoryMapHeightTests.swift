//
//  MemoryMapHeightTests.swift
//  TwofoldTests
//
//  The Add Memory screen's map gives up its height as the form scrolls. The arithmetic is trivial;
//  the clamping isn't optional. Shrinking the map grows the scroll view, and a growing scroll view
//  can nudge its own offset back at the bottom of the content — so a height that tracked the offset
//  unclamped would feed back into it and oscillate.
//

import Testing
import Foundation
@testable import Twofold

struct MemoryMapHeightTests {

    private let screen: CGFloat = 800
    private var expanded: CGFloat { screen * MemoryMapHeight.expandedFraction }
    private var collapsed: CGFloat { screen * MemoryMapHeight.collapsedFraction }

    private func height(_ offset: CGFloat, editingNote: Bool = false) -> CGFloat {
        MemoryMapHeight.forOffset(offset, availableHeight: screen, isEditingNote: editingNote)
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

    /// The clamp that stops the oscillation: past the collapse point, more scrolling changes
    /// nothing, so an offset nudged back by the growing scroll view can't grow the map again.
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

    /// The keyboard takes the bottom half of the screen, so this one case isn't gradual.
    @Test("editing the note collapses the map immediately, whatever the scroll")
    func editingNoteOverridesScroll() {
        #expect(height(0, editingNote: true) == collapsed)
        #expect(height(500, editingNote: true) == collapsed)
    }

    @Test("the map always keeps enough height to show the pin")
    func neverDisappears() {
        for offset in stride(from: CGFloat(0), through: 2000, by: 50) {
            #expect(height(offset) >= collapsed)
        }
    }
}
