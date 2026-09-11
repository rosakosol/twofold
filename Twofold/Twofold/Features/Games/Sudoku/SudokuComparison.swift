//
//  SudokuComparison.swift
//  Twofold
//
//  Two finished times and what to say about them.
//
//  Separate from `SudokuComparisonView` because the rules here are the kind that go wrong quietly:
//  a rounding choice that awards a win to two times that read identically on screen, or a margin
//  phrased as "187s ahead". None of that crashes, and none of it is visible from a screenshot of
//  the happy path — so it lives where a test can reach it.
//

import Foundation

/// One finished solve, as much of it as a comparison needs.
struct SudokuSolveSummary: Equatable {
    let elapsed: TimeInterval
    let hintsUsed: Int
    let checksUsed: Int

    var isUnaided: Bool { hintsUsed == 0 && checksUsed == 0 }

    /// "2 hints", "checked twice", "2 hints, checked once" — or nil when nothing was used, because
    /// "no help" printed under both times is noise on the ordinary case.
    var aidsDescription: String? {
        var parts: [String] = []
        if hintsUsed > 0 { parts.append(hintsUsed == 1 ? "1 hint" : "\(hintsUsed) hints") }
        if checksUsed > 0 {
            parts.append(checksUsed == 1 ? "checked once" : checksUsed == 2 ? "checked twice" : "checked \(checksUsed) times")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct SudokuComparison: Equatable {
    enum Outcome: Equatable {
        case me
        case partner
        case tie
    }

    let myElapsed: TimeInterval
    let partnerElapsed: TimeInterval
    let partnerName: String
    /// What each of them used. Defaulted so the many call sites that only care about the two times
    /// — tests, previews, the share card's own construction — stay readable.
    var myAids: SudokuSolveSummary?
    var partnerAids: SudokuSolveSummary?

    /// True when one of them solved it unaided and the other did not.
    ///
    /// This is the case the screen has to be careful about: the times are comparable arithmetic but
    /// not comparable achievements, and showing a winner without saying why would be the race
    /// quietly rewarding whoever was most willing to ask.
    var isLopsided: Bool {
        guard let mine = myAids, let theirs = partnerAids else { return false }
        return mine.isUnaided != theirs.isUnaided
    }

    /// Positive when this player was quicker, negative when the partner was, zero for a dead heat.
    ///
    /// Truncated to whole seconds the same way `clockText` truncates them, so the margin is always
    /// the gap between the two times *as the rows display them*. Two things go wrong otherwise, and
    /// both leave a verdict that contradicts the numbers directly above it:
    ///
    ///   * Comparing the raw `TimeInterval`s lets two solves a fraction apart — both reading 2:14 —
    ///     produce a winner and a "0s ahead" line to justify it.
    ///   * Rounding instead of truncating turns 134.6 into 135 while the row still says 2:14, so a
    ///     six-second gap is announced as five.
    ///
    /// In practice `elapsed` is always whole seconds (the clock adds 1 at a time, and a restored
    /// state decodes an `Int`), so this is about staying correct rather than being reachable today.
    var margin: Int { Int(partnerElapsed) - Int(myElapsed) }

    var outcome: Outcome {
        if margin > 0 { return .me }
        if margin < 0 { return .partner }
        return .tie
    }

    var verdict: String {
        switch outcome {
        case .tie:
            "A dead heat — you both took \(SudokuComparison.clockText(myElapsed))."
        case .me:
            "You finished \(Self.gapText(margin)) ahead."
        case .partner:
            "\(partnerName) finished \(Self.gapText(-margin)) ahead."
        }
    }

    /// The same verdict for a card that leaves the device.
    ///
    /// "You" is only meaningful to whoever is holding the phone. On a shared image it names the
    /// sender to everyone else — including the partner it is most likely to be sent to, who would
    /// read someone else's win as their own — so both sides are named outright here.
    func sharedVerdict(myName: String) -> String {
        switch outcome {
        case .tie:
            "A dead heat — \(Self.clockText(myElapsed)) each."
        case .me:
            "\(myName) finished \(Self.gapText(margin)) ahead."
        case .partner:
            "\(partnerName) finished \(Self.gapText(-margin)) ahead."
        }
    }

    /// Seconds up to a minute, clock formatting beyond it — "48s ahead" reads better than
    /// "0:48 ahead", while "3:07 ahead" reads better than "187s ahead".
    static func gapText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : clockText(TimeInterval(seconds))
    }

    /// `m:ss`, or `h:mm:ss` once a puzzle has run past an hour — which an Expert grid left open
    /// across a few sittings genuinely does.
    static func clockText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
