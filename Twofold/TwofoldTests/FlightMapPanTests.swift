//
//  FlightMapPanTests.swift
//  TwofoldTests
//
//  The flight detail map is inside that screen's ScrollView, and a scroll view claims a drag that
//  starts anywhere in its content — including on a subview holding a pan recogniser of its own. So
//  the map read as interactive and wasn't: pinch worked, dragging scrolled the page past the map
//  rather than panning it, and the recentre button had nothing to recentre from.
//
//  The fix switches the enclosing scroll view off for the duration of a touch on the map. The two
//  things that can go wrong with that are both asserted here: finding the wrong scroll view (the
//  map has several of its own, inside it), and failing to switch scrolling back on — which would
//  leave the whole screen frozen.
//

import Testing
import MapKit
import UIKit
@testable import Twofold

@MainActor
struct FlightMapPanTests {

    /// The real arrangement: a page that scrolls, with a map somewhere inside it.
    private func page() -> (scrollView: UIScrollView, map: MKMapView) {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 2000))
        let map = MKMapView(frame: CGRect(x: 0, y: 300, width: 402, height: 260))
        content.addSubview(map)
        scrollView.addSubview(content)
        return (scrollView, map)
    }

    /// Walking *up* is the whole point. MKMapView contains scroll views of its own; finding one of
    /// those and disabling it would take away the map's panning rather than the page's — the exact
    /// opposite of the fix.
    @Test("the scroll view found is the page's, not one of the map's own")
    func findsTheEnclosingScrollView() {
        let (scrollView, map) = page()
        let found = MapKitRouteView.Coordinator.enclosingScrollView(of: map)
        #expect(found === scrollView)
    }

    /// Upward only. Anything scrollable inside the map belongs to the map, and switching that off
    /// would take away the very panning this is meant to give back — so a scroll view nested below
    /// must be ignored even though it is nearer.
    ///
    /// (Written as a constructed case rather than by inspecting MKMapView's own subviews: an
    /// earlier version of this test asserted the map nests scroll views internally, and on this
    /// iOS version it does not — it found none and failed. The rule is about direction, not about
    /// what MapKit happens to build today.)
    @Test("a scroll view inside the map is ignored")
    func ignoresScrollViewsBelow() {
        let (scrollView, map) = page()
        let inner = UIScrollView(frame: map.bounds)
        map.addSubview(inner)
        let probe = UIView(frame: map.bounds)
        inner.addSubview(probe)

        // Asked from the map, the answer is the page above it — never the one just added below.
        #expect(MapKitRouteView.Coordinator.enclosingScrollView(of: map) === scrollView)
        // And asked from inside that nested one, the nested one is correctly the nearest ancestor,
        // which is why the call site passes the map itself rather than whatever was touched.
        #expect(MapKitRouteView.Coordinator.enclosingScrollView(of: probe) === inner)
    }

    /// A map that isn't inside anything scrollable must not go looking for one.
    @Test("a map with no scrolling ancestor finds nothing")
    func noAncestorFindsNothing() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 402, height: 260))
        UIView().addSubview(map)
        #expect(MapKitRouteView.Coordinator.enclosingScrollView(of: map) == nil)
    }

    /// And the one that would be a disaster to get wrong: scrolling comes back. A coordinator torn
    /// down mid-touch — swiping back to the flight list while a finger is still on the map — must
    /// not leave the screen unable to scroll.
    @Test("scrolling is restored when the map goes away mid-touch")
    func scrollingIsRestoredOnTeardown() {
        let (scrollView, map) = page()
        let coordinator = MapKitRouteView.Coordinator()

        let recognizer = UILongPressGestureRecognizer()
        map.addGestureRecognizer(recognizer)
        coordinator.suspendScrollForTesting(around: map)
        #expect(!scrollView.isScrollEnabled, "the page should stop scrolling while the map is being dragged")

        coordinator.restoreEnclosingScroll()
        #expect(scrollView.isScrollEnabled, "the page never scrolled again")
    }

    /// Restoring twice, or without ever having suspended, must be harmless — `dismantleUIView`
    /// calls it on every teardown regardless of whether a touch was in progress.
    @Test("restoring is safe to call at any time")
    func restoringIsIdempotent() {
        let (scrollView, _) = page()
        let coordinator = MapKitRouteView.Coordinator()
        coordinator.restoreEnclosingScroll()
        coordinator.restoreEnclosingScroll()
        #expect(scrollView.isScrollEnabled)
    }
}

//
//  The camera lock, and why panning worked only sometimes.
//
//  While a flight is airborne the map recentres on the plane once a second. Whether that counted as
//  "the user panned" was inferred from `regionDidChangeAnimated`, filtered by a single
//  `isProgrammaticCameraChange` flag that the *next* callback consumes — so a pan whose callback
//  arrived while one of those recentres was in flight got swallowed as the app's own, follow stayed
//  on, and the next tick pulled the camera back. Whether a drag "worked" came down to where in the
//  one-second cycle the finger landed.
//
@MainActor
struct FlightMapCameraLockTests {

    private func page() -> (scrollView: UIScrollView, map: MKMapView) {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let map = MKMapView(frame: CGRect(x: 0, y: 300, width: 402, height: 260))
        scrollView.addSubview(map)
        return (scrollView, map)
    }

    /// Touching the map releases the lock, with no reference to any region callback.
    @Test("a touch releases the camera lock")
    func touchReleasesTheLock() {
        let (_, map) = page()
        let coordinator = MapKitRouteView.Coordinator()
        coordinator.isFollowing = true

        coordinator.beginTouchForTesting(on: map)
        #expect(!coordinator.isFollowing)
    }

    /// The race, reproduced. A programmatic recentre is mid-flight — the flag that used to decide
    /// this is set — and the user touches the map anyway. Under the old rule that touch was
    /// indistinguishable from the app's own camera move; it must now release the lock regardless.
    @Test("a touch during a programmatic recentre still releases the lock")
    func touchDuringRecentreStillReleases() {
        let (_, map) = page()
        let coordinator = MapKitRouteView.Coordinator()
        coordinator.isFollowing = true
        coordinator.markProgrammaticCameraChangeForTesting()

        coordinator.beginTouchForTesting(on: map)
        #expect(!coordinator.isFollowing, "this is the case where panning silently did nothing")
    }

    /// The lock's state is reported outward, which is what lets the button show whether it is on.
    /// Only on real changes — the button would otherwise re-animate every second as the follow
    /// camera ticks.
    @Test("the lock reports its state, once per change")
    func lockReportsItsState() {
        let coordinator = MapKitRouteView.Coordinator()
        var reported: [Bool] = []
        coordinator.onFollowingChanged = { reported.append($0) }

        coordinator.isFollowing = true
        coordinator.isFollowing = true
        coordinator.isFollowing = false
        #expect(reported == [true, false], "got \(reported)")
    }
}
