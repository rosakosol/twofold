//
//  WordSearchComparison.swift
//  Twofold
//
//  Two finished grids and what to say about them.
//
//  The simplest of the three comparisons, because a word search has no failure state and no way to
//  ask for help: every grid can be finished, everyone finishes with all eight, and the only thing
//  that differs is how long it took. So this is a straight race — the one place in these games
//  where time genuinely is the whole result.
//
//  Which is exactly why it is still its own type rather than borrowing sudoku's. That one carries
//  hints and checks and a lopsided-race warning that has no meaning here, and a comparison that
//  quietly answers questions nobody asked is a comparison somebody will eventually believe.
//

import Foundation

struct WordSearchComparison: Equatable {
    enum Outcome: Equatable {
        case me
        case partner
        case tie
    }

    let myElapsed: TimeInterval
    let partnerElapsed: TimeInterval
    let partnerName: String
    let theme: WordSearchTheme

    /// Positive when this player was quicker, negative when the partner was, zero for a dead heat.
    ///
    /// Truncated to whole seconds the way `PuzzleClock.text` truncates them, so the margin is the
    /// gap between the two times *as the rows display them*. Comparing the raw intervals instead
    /// lets two times that both read 3:41 produce a winner and a "0s ahead" line to justify it —
    /// a result the player can see the rows contradict.
    var margin: Int { Int(partnerElapsed) - Int(myElapsed) }

    var outcome: Outcome {
        if margin > 0 { return .me }
        if margin < 0 { return .partner }
        return .tie
    }

    /// `LocalizedStringResource`, not `String` — see `SudokuComparison.verdict`.
    var verdict: LocalizedStringResource {
        switch outcome {
        case .tie:
            LocalizedStringResource(
                "A dead heat — you both took \(PuzzleClock.text(myElapsed)).",
                comment: "Word Search comparison when both grids took the same time. The value is a duration like “4:00”."
            )
        case .me:
            LocalizedStringResource(
                "You cleared the grid \(PuzzleClock.gapText(margin)) faster.",
                comment: "Word Search comparison, this player won. The value is a duration like “48s” or “3:07”."
            )
        case .partner:
            LocalizedStringResource(
                "\(partnerName) cleared the grid \(PuzzleClock.gapText(-margin)) faster.",
                comment: "Word Search comparison, the partner won. First value is their name, second is a duration like “48s” or “3:07”."
            )
        }
    }

    /// The same verdict for a card that leaves the device, where "you" names the sender to everyone
    /// looking at it — including the partner, who would read someone else's win as their own.
    func sharedVerdict(myName: String) -> LocalizedStringResource {
        switch outcome {
        case .tie:
            LocalizedStringResource(
                "A dead heat — \(PuzzleClock.text(myElapsed)) each.",
                comment: "Shareable Word Search card, both times equal. The value is a duration like “4:00”."
            )
        case .me, .partner:
            LocalizedStringResource(
                "\(outcome == .me ? myName : partnerName) cleared the grid \(PuzzleClock.gapText(abs(margin))) faster.",
                comment: "Shareable Word Search card. First value is the winner's name, second is a duration like “48s” or “3:07”."
            )
        }
    }
}
