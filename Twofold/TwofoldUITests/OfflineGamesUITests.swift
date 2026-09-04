//
//  OfflineGamesUITests.swift
//  TwofoldUITests
//
//  Playing a deck with no connection, on the clock.
//
//  Correctness was never the whole problem here. The offline paths worked, but every one of them
//  reached the on-device catalogue only *after* a backend call had failed — and a call with no
//  network doesn't fail, it waits out a URLSession timeout first. The deck list, the daily-question
//  card, opening a deck, and every round in it each paid that separately, so a game that was
//  entirely local took minutes to play. Reported as "very very slow, and subsequent rounds don't
//  load", which is what a stack of 60-second timeouts looks like from the outside.
//
//  So these assert on *time*, not just on things appearing.
//
//  "Offline" here is `TWOFOLD_FORCE_OFFLINE` (see `NetworkMonitor`), not the Mac's Wi-Fi switch.
//  Switching off the real adapter disconnects the simulator, the test runner and everything else
//  on the machine along with it, which is why this behaviour went untested long enough to ship a
//  minute of timeouts.
//
//  Requires a simulator already signed in — see `SignInUITests`.
//

import XCTest

final class OfflineGamesUITests: XCTestCase {

    /// Generous next to a 60-second URLSession timeout, and tight enough that hitting even one
    /// would fail this. The point isn't the exact number, it's that nothing is waiting on a
    /// network call that cannot succeed.
    private let budget: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testGamesHubAndADeckOpenPromptlyWithNoNetwork() throws {
        let app = XCUIApplication()
        // Set `TWOFOLD_TEST_ONLINE=1` to run the same measurements against a live backend — the
        // budget applies either way, since "slow" was reported without saying which.
        if ProcessInfo.processInfo.environment["TWOFOLD_TEST_ONLINE"] != "1" {
            app.launchEnvironment["TWOFOLD_FORCE_OFFLINE"] = "1"
        }
        app.launch()

        let gamesTab = app.buttons["Games"]
        guard gamesTab.waitForExistence(timeout: 30) else {
            throw XCTSkip("Not signed in — run SignInUITests first.")
        }

        let openedHub = Date()
        gamesTab.tap()

        // Any deck at all. The hub groups them under topic sections, so the reliable signal that
        // the catalogue arrived is that something tappable inside the scroll view exists.
        let firstDeck = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(
            firstDeck.waitForExistence(timeout: budget),
            "No decks within \(Int(budget))s — the hub is waiting on a network call instead of reading the on-device catalogue"
        )
        let hubTime = Date().timeIntervalSince(openedHub)
        XCTAssertLessThan(hubTime, budget, "Games hub took \(hubTime)s offline")

        let openedDeck = Date()
        firstDeck.tap()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: budget)

        // Either the deck opens to its first round, or it says plainly that this one needs a
        // connection — both are prompt answers. What must not happen is a spinner for a minute.
        // Waits on the navigation bar rather than a broad `staticTexts` sweep: querying every
        // label on a game screen mid-animation times the query itself out.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: budget))
        let deckTime = Date().timeIntervalSince(openedDeck)
        XCTAssertLessThan(deckTime, budget, "Deck took \(deckTime)s to open offline")

        // Round-to-round, which is the other half of "loads the first screen but subsequent rounds
        // don't" — a deck that opens and then stalls is worse than one that never opens, because
        // by then the couple has committed to playing it.
        //
        // Only the decks with a "Next" button (deep conversations) are measured; the others answer
        // through a swipe, and driving that reliably is a bigger job than it's worth here. Which
        // deck the hub happens to list first isn't fixed, so this walks a few until it finds one
        // rather than silently skipping the measurement that matters most.
        //
        // Deliberately not walking deck to deck looking for one: `app.scrollViews.buttons`
        // indexed past the first times the *query* out on this screen — the hub carries 191 decks,
        // and enumerating that hierarchy is slower than anything it would measure.
        // `GameSessionStoreOfflineTests` covers round-to-round directly instead.
        let next = app.buttons["Next"]
        guard next.waitForExistence(timeout: 3) else {
            print("OFFLINE_TIMING hub=\(hubTime)s deck=\(deckTime)s round=not-a-next-button-deck")
            return
        }
        let tappedNext = Date()
        next.tap()
        XCTAssertTrue(
            next.waitForExistence(timeout: budget),
            "The next round never became answerable — the deck opened and then stalled"
        )
        let roundTime = Date().timeIntervalSince(tappedNext)
        XCTAssertLessThan(roundTime, budget, "Next round took \(roundTime)s")

        print("OFFLINE_TIMING hub=\(hubTime)s deck=\(deckTime)s round=\(roundTime)s")
    }
}
