//
//  LocalGameSessionSync.swift
//  Twofold
//
//  Turning a deck played offline into a real session once there's a connection.
//
//  Runs before `GameSessionStore.syncPendingResponses()` and has to: that drain submits each
//  queued answer against the session id it was recorded under, and for a game started offline that
//  id exists only on this device. Left alone it would fail every time, forever, and the answers
//  would sit in the queue until someone cleared the app.
//
//  Answers are remapped by content id, never by round number. `start_deck_session` builds its
//  rounds with `array_agg` and no `order by`, so the real session's round 3 is not reliably the
//  round 3 the couple answered on the plane — but it holds one of the same questions, and that is
//  what the mapping keys on.
//

import Foundation

enum LocalGameSessionSync {

    /// Guards against two drains overlapping — this is called on reconnect and on the Games hub
    /// appearing, which can land together.
    private nonisolated(unsafe) static var isFlushing = false
    private static let lock = NSLock()

    /// Promotes every locally started session that has answers waiting. Returns true if anything
    /// changed, so the caller can refresh the deck list it just made stale.
    @discardableResult
    static func flush() async -> Bool {
        lock.lock()
        if isFlushing { lock.unlock(); return false }
        isFlushing = true
        lock.unlock()
        defer { lock.lock(); isFlushing = false; lock.unlock() }

        var changed = false
        for local in LocalGameSessionStore.all() {
            if await promote(local) { changed = true }
        }
        return changed
    }

    private static func promote(_ local: LocalGameSession) async -> Bool {
        let queued = PendingGameResponseStore.forSession(local.id)
        guard !queued.isEmpty else {
            // Opened offline and never answered. Nothing to preserve, and keeping it would let a
            // stale round order resurface later under a deck the couple has since played online.
            LocalGameSessionStore.remove(id: local.id)
            return false
        }

        // Ask the backend to start the deck for real. This is also where the tier and partner
        // rules are finally enforced — `LocalGameSessionStore.canStart` mirrors them so this
        // rarely fails, but if it does the answers are dropped rather than retried forever
        // against a session that will never exist.
        guard let realSessionID = try? await BackendService.startDeckSession(deckID: local.deckID) else {
            return false
        }
        guard let detail = try? await BackendService.fetchGameSession(id: realSessionID) else {
            // The session exists but its rounds are unreadable right now. Leave everything queued
            // and try again on the next reconnect — but the local session is gone from the
            // backend's point of view, so remember the id we already made rather than making a
            // second one next time.
            return false
        }

        var roundForContent: [UUID: Int] = [:]
        for round in detail.rounds { roundForContent[round.contentID] = round.roundNumber }

        for item in queued {
            guard let contentID = item.contentID ?? local.contentID(forRound: item.roundNumber),
                  let roundNumber = roundForContent[contentID] else {
                // The question is no longer in the deck — deactivated server-side between the
                // flight and the landing. There is nowhere to put the answer.
                PendingGameResponseStore.remove(id: item.id)
                continue
            }
            do {
                try await BackendService.submitGameResponse(
                    sessionID: realSessionID,
                    roundNumber: roundNumber,
                    answerValue: item.answerValue,
                    isCorrect: item.isCorrect
                )
                PendingGameResponseStore.remove(id: item.id)
            } catch {
                // Left queued, same as the online path: an upsert is safe to retry, and dequeuing
                // on failure would lose the answer instead of retrying a transient error.
            }
        }

        // Only once nothing is left pointing at the local id — otherwise the mapping needed to
        // place those answers would be gone.
        if PendingGameResponseStore.forSession(local.id).isEmpty {
            LocalGameSessionStore.remove(id: local.id)
        }
        return true
    }
}
