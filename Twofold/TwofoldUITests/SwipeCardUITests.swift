//
//  SwipeCardUITests.swift
//  TwofoldUITests
//
//  Drives the real swipe card in This or That / Who's More Likely.
//
//  Only drags *below* the commit threshold, because that is the path the stuck-card fix is about:
//  whether the card comes back when a drag doesn't commit. These used to be opt-in because they
//  opened a session in a real couple's account on production; they now run as a freshly paired
//  Plus couple on the local stack, so opening a deck costs nobody anything.
//

import XCTest

final class SwipeCardUITests: E2ETestCase {

    /// Opens a swipe-based deck and returns the card element.
    ///
    /// A fresh Plus couple with a This or That session already started on a deck that has prompts
    /// here, opened the way tapping that game's push opens it (`-notificationRoute game:…`).
    ///
    /// It used to tap whichever deck the Games hub listed first. Against the local stack that is
    /// often a deck with no prompts — the deck rows come from migrations, some of their content
    /// does not — and the start is refused, so which deck is played is now the scenario's choice.
    @MainActor
    private func openSwipeGame() async throws -> (XCUIApplication, XCUIElement) {
        let scenario = try await Scenario.pairedPlus()
        let session = try await scenario.startDeck(gameType: "this_or_that")
        let app = launch(scenario, arguments: ["-notificationRoute", "game:this_or_that:\(session)"])
        waitForSignedInApp(app)

        // The card combines its content into one element, which always includes the round counter
        // ("1 of 8" now, "1 / 8" before), so that's the stable thing to match on.
        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES[c] '.*[0-9]+ (/|of) [0-9]+.*'")
        ).firstMatch
        if !card.waitForExistence(timeout: 12) {
            print("=== NO CARD FOUND; TREE ===")
            print(app.debugDescription)
            print("=== END TREE ===")
            XCTFail("Could not reach a swipe card")
        }
        return (app, card)
    }

    /// A drag that stops short of the threshold must leave the card back at rest. Before the fix
    /// the card was only ever returned by `onEnded`, so anything that ended the drag another way
    /// left it parked mid-screen.
    @MainActor
    func testShortDragLeavesTheCardBackAtRest() async throws {
        let (app, card) = try await openSwipeGame()

        let before = card.frame
        XCTAssertGreaterThan(before.width, 0, "card has no frame to drag")

        // ~60pt across — well under SwipeChoiceCard's 110pt commit threshold.
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Give the spring time to settle.
        try await Task.sleep(for: .seconds(1))

        let after = card.frame
        let drift = abs(after.midX - before.midX)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "swipe-short-drag-settled"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertLessThan(
            drift, 8,
            "Card settled \(drift)pt from where it started — a drag that didn't commit should return it to rest."
        )
    }

    /// Several short drags in a row must each return the card. A card that latched after the first
    /// one would show up here as the second drag moving nothing.
    @MainActor
    func testRepeatedShortDragsKeepWorking() async throws {
        let (_, card) = try await openSwipeGame()

        let origin = card.frame.midX

        for attempt in 1...3 {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: attempt.isMultiple(of: 2) ? -70 : 70, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: end)
            try await Task.sleep(for: .seconds(1))

            let drift = abs(card.frame.midX - origin)
            XCTAssertLessThan(drift, 8, "Card did not return to rest after drag \(attempt) (off by \(drift)pt)")
        }
    }

    /// A drag started hard against the screen's left edge, where the navigation controller's
    /// interactive back-swipe competes for the touch.
    ///
    /// Worth being precise about what this does and doesn't prove: it passes both with and without
    /// the cancellation fix, so it is a smoke test, not a reproduction. XCUITest's synthesized
    /// drags don't appear to provoke the recognizer hand-off that cancels a real finger's gesture,
    /// and there's no API to cancel a touch outright. Kept because an edge-started drag stranding
    /// the card would still be caught here, but the cancellation path itself remains unverified by
    /// automation — see the note in SwipeChoiceCard.
    @MainActor
    func testDragStartingAtTheScreenEdgeDoesNotStrandTheCard() async throws {
        let (app, card) = try await openSwipeGame()

        let resting = card.frame.midX

        // Absolute window coordinates: hard against the left edge, vertically level with the card.
        let cardMidYFraction = card.frame.midY / app.frame.height
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.004, dy: cardMidYFraction))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 70, dy: 0)))

        try await Task.sleep(for: .seconds(1.2))

        guard card.exists else {
            throw XCTSkip("The edge drag popped the screen rather than being cancelled — nothing to assert.")
        }

        let drift = abs(card.frame.midX - resting)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "swipe-edge-drag-settled"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertLessThan(
            drift, 8,
            "Card was left \(drift)pt off-centre after an edge drag — a cancelled gesture stranded it mid-swipe."
        )
    }
}
