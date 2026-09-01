//
//  WidgetDeepLinkTests.swift
//  TwofoldTests
//
//  Every URL a widget puts on screen, parsed the way `RootView.onOpenURL` parses a real tap.
//
//  These fail silently when wrong: an unparseable URL returns nil and the tap opens the app on
//  whatever it happened to be showing, which is indistinguishable from a widget that simply isn't
//  linked. Several were pointed at `twofold://home` regardless of what they displayed — tapping a
//  trip countdown, or a day count for the relationship, dropped you on the Home tab.
//

import Testing
import Foundation
@testable import Twofold

struct WidgetDeepLinkTests {

    private func destination(_ string: String) -> WidgetDeepLink.Destination? {
        WidgetDeepLink.destination(for: URL(string: string)!)
    }

    // MARK: - The two halves of the Medium drawing pad

    /// `widgetURL` can only name one destination for a whole widget, so the side-by-side pads use
    /// a `Link` each. These are the two they point at, and they must not be the same one.
    @Test func theTwoDrawingPadsAreDifferentDestinations() {
        #expect(destination("twofold://drawing-pad") == .drawingPad)
        #expect(destination("twofold://partner-drawing-pad") == .partnerDrawingPad)
        #expect(destination("twofold://drawing-pad") != destination("twofold://partner-drawing-pad"))
    }

    // MARK: - Days Together

    /// The Stats tab remembers whichever card was last open, so this widget has to name the one it
    /// means rather than just asking for the tab.
    @Test func daysTogetherOpensTheRelationshipCard() {
        #expect(destination("twofold://passport/relationship") == .passport(.relationship))
    }

    @Test func theStatsTabIsStillReachableWithoutNamingACard() {
        #expect(destination("twofold://passport") == .passport(nil))
    }

    /// The section names are the *display* strings ("Relationship"), which a URL path shouldn't
    /// have to carry the capitalisation of.
    @Test func aStatsSectionMatchesWhateverTheCasing() {
        #expect(destination("twofold://passport/Relationship") == .passport(.relationship))
        #expect(destination("twofold://passport/trips") == .passport(.trips))
        #expect(destination("twofold://passport/FLIGHTS") == .passport(.flights))
    }

    /// A card name this build doesn't know must still land on Stats rather than nowhere.
    @Test func anUnknownStatsSectionStillOpensTheTab() {
        #expect(destination("twofold://passport/wardrobe") == .passport(nil))
    }

    // MARK: - Trip countdown

    @Test func tripCountdownOpensThatTrip() throws {
        let id = UUID()
        #expect(destination("twofold://trip/\(id.uuidString)") == .trip(id))
    }

    /// The widget falls back to Home when the snapshot predates `ReunionInfo` carrying an id — so
    /// a trip URL with nothing after it must not resolve to some other trip.
    @Test func aTripURLWithoutAnIdResolvesToNothing() {
        #expect(destination("twofold://trip") == nil)
        #expect(destination("twofold://trip/not-a-uuid") == nil)
    }

    // MARK: - The rest, unchanged

    @Test func everyOtherWidgetURLStillResolves() throws {
        let flightID = UUID()
        let memoryID = UUID()
        #expect(destination("twofold://paywall") == .paywall)
        #expect(destination("twofold://home") == .home)
        #expect(destination("twofold://memories") == .memories)
        #expect(destination("twofold://flight/\(flightID.uuidString)") == .flight(flightID))
        #expect(destination("twofold://memory/\(memoryID.uuidString)") == .memory(memoryID))
    }

    @Test func aForeignSchemeIsIgnored() {
        #expect(destination("https://twofold.app/passport/relationship") == nil)
        #expect(destination("twofold://somewhere-we-dont-ship") == nil)
    }
}
