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

    /// "2 hints", "checked once", "2 hints, checked 3 times" — or nil when nothing was used,
    /// because "no help" printed under both times is noise on the ordinary case.
    ///
    /// Each count goes through a plural key in the String Catalog rather than a Swift ternary.
    /// English has two plural forms and the ternary quietly assumed that; Polish has three and
    /// Arabic six, so `count == 1 ? "hint" : "hints"` is not a rule that survives translation. The
    /// catalog is the only place that rule can live per language.
    ///
    /// This did say "checked twice" for exactly two. That reads better in English and has no
    /// equivalent in most languages — it is a special case English happens to have a word for, not
    /// a plural category — so it is gone rather than being a branch no translator could reproduce.
    ///
    /// The two halves are still joined with a comma here. Properly, a sentence inflected on two
    /// counts at once wants a single key with substitutions for both; that is worth doing when
    /// there is a translator to do it for, and the comma is honest until then.
    var aidsDescription: String? {
        var parts: [String] = []
        if hintsUsed > 0 {
            parts.append(String(localized: "\(hintsUsed) hints"))
        }
        if checksUsed > 0 {
            parts.append(String(localized: "checked \(checksUsed) times"))
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
    /// Truncated to whole seconds the same way `PuzzleClock.text` truncates them, so the margin is always
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

    /// `LocalizedStringResource`, not `String`.
    ///
    /// A sentence returned as a plain `String` and handed to `Text` is shipped verbatim — the
    /// `Text(_: LocalizedStringKey)` initializer that makes every literal in the app translatable
    /// is not the one it hits, and Xcode's string extractor cannot see it either. It would be
    /// invisible to the String Catalog forever, which for the one sentence on this screen that says
    /// who won is not a good place to be invisible.
    var verdict: LocalizedStringResource {
        switch outcome {
        case .tie:
            LocalizedStringResource(
                "A dead heat — you both took \(PuzzleClock.text(myElapsed)).",
                comment: "Sudoku comparison when both solves took the same time. The value is a duration like “4:00”."
            )
        case .me:
            LocalizedStringResource(
                "You finished \(PuzzleClock.gapText(margin)) ahead.",
                comment: "Sudoku comparison, this player won. The value is a duration like “48s” or “3:07”."
            )
        case .partner:
            LocalizedStringResource(
                "\(partnerName) finished \(PuzzleClock.gapText(-margin)) ahead.",
                comment: "Sudoku comparison, the partner won. First value is their name, second is a duration like “48s” or “3:07”."
            )
        }
    }

    /// The same verdict for a card that leaves the device.
    ///
    /// "You" is only meaningful to whoever is holding the phone. On a shared image it names the
    /// sender to everyone else — including the partner it is most likely to be sent to, who would
    /// read someone else's win as their own — so both sides are named outright here.
    ///
    /// Rendered in the sender's language, since they are the one making the picture.
    func sharedVerdict(myName: String) -> LocalizedStringResource {
        switch outcome {
        case .tie:
            LocalizedStringResource(
                "A dead heat — \(PuzzleClock.text(myElapsed)) each.",
                comment: "Shareable sudoku card, both times equal. The value is a duration like “4:00”."
            )
        case .me, .partner:
            // One key for both, since the card names whoever won either way — and two keys saying
            // the same sentence is two things for a translator to keep in step.
            LocalizedStringResource(
                "\(outcome == .me ? myName : partnerName) finished \(PuzzleClock.gapText(abs(margin))) ahead.",
                comment: "Shareable sudoku card. First value is the winner's name, second is a duration like “48s” or “3:07”."
            )
        }
    }

}
