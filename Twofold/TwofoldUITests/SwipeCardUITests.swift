//
//  SwipeCardUITests.swift
//  TwofoldUITests
//
//  Drives the real swipe card in This or That / Who's More Likely.
//
//  Deliberately only drags *below* the commit threshold. This simulator talks to production, and a
//  committed swipe submits a real answer into the couple's live session — a below-threshold drag
//  exercises the same gesture path and writes nothing. It's also the path the stuck-card fix is
//  about: whether the card comes back when a drag doesn't commit.
//

import XCTest

final class SwipeCardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens a swipe-based deck and returns the card element.
    ///
    /// Only sub-threshold drags are ever performed on it, so no answer is submitted — but opening
    /// the deck does start a session, which is why this test is opt-in rather than part of the
    /// default suite.
    @MainActor
    private func openSwipeGame(_ app: XCUIApplication) throws -> XCUIElement {
        let games = app.buttons["Games"]
        guard games.waitForExistence(timeout: 30) else {
            throw XCTSkip("Not signed in on this simulator.")
        }
        games.tap()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)

        // A deck card, not the game-type tile above it — both mention the game's name, but only a
        // deck's label carries its question count (see DeckCardRow's combined label).
        let deck = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'questions' AND (label CONTAINS[c] 'THIS OR THAT' OR label CONTAINS[c] 'MORE LIKELY')")
        ).firstMatch
        guard deck.waitForExistence(timeout: 10) else {
            throw XCTSkip("No swipe-based deck on the Games hub to open.")
        }
        deck.tap()

        // The deck entry screen sits between the list and the first card.
        let startButton = app.buttons.matching(
            NSPredicate(format: "label MATCHES[c] '.*(start|play|resume|continue).*'")
        ).firstMatch
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        }

        // The card combines its content into one element, which always includes the round counter
        // ("1 / 8"), so that's the stable thing to match on.
        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES[c] '.*[0-9]+ / [0-9]+.*'")
        ).firstMatch
        if !card.waitForExistence(timeout: 12) {
            print("=== NO CARD FOUND; TREE ===")
            print(app.debugDescription)
            print("=== END TREE ===")
            XCTFail("Could not reach a swipe card")
        }
        return card
    }

    /// A drag that stops short of the threshold must leave the card back at rest. Before the fix
    /// the card was only ever returned by `onEnded`, so anything that ended the drag another way
    /// left it parked mid-screen.
    @MainActor
    func testShortDragLeavesTheCardBackAtRest() throws {
        let app = XCUIApplication()
        app.launch()
        let card = try openSwipeGame(app)

        let before = card.frame
        XCTAssertGreaterThan(before.width, 0, "card has no frame to drag")

        // ~60pt across — well under SwipeChoiceCard's 110pt commit threshold.
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Give the spring time to settle.
        Thread.sleep(forTimeInterval: 1.0)

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
    func testRepeatedShortDragsKeepWorking() throws {
        let app = XCUIApplication()
        app.launch()
        let card = try openSwipeGame(app)

        let origin = card.frame.midX

        for attempt in 1...3 {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: attempt.isMultiple(of: 2) ? -70 : 70, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 1.0)

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
    func testDragStartingAtTheScreenEdgeDoesNotStrandTheCard() throws {
        let app = XCUIApplication()
        app.launch()
        let card = try openSwipeGame(app)

        let resting = card.frame.midX

        // Absolute window coordinates: hard against the left edge, vertically level with the card.
        let cardMidYFraction = card.frame.midY / app.frame.height
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.004, dy: cardMidYFraction))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 70, dy: 0)))

        Thread.sleep(forTimeInterval: 1.2)

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
