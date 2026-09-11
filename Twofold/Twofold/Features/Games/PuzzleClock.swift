//
//  PuzzleClock.swift
//  Twofold
//
//  How long a puzzle took, written the same way everywhere it appears.
//
//  These two lived on `SudokuComparison` while sudoku was the only game with a clock. Word Guess
//  then reached across to `SudokuComparison.clockText` for its own times, which is the point at
//  which a helper has outgrown the type it is attached to — and Word Search would have been the
//  third to do it.
//
//  It matters that there is one implementation rather than three that agree today. A running clock
//  and a finished time have to match to the second: a solve that ended at 2:14 on the play screen
//  cannot become 2:13 on the comparison beside it, and two copies of the same rounding rule is how
//  that eventually happens.
//

import Foundation

enum PuzzleClock {

    /// `m:ss`, or `h:mm:ss` once a puzzle has run past an hour — which an Expert sudoku left open
    /// across a few sittings genuinely does.
    static func text(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The gap between two times: seconds up to a minute, clock formatting beyond it — "48s ahead"
    /// reads better than "0:48 ahead", while "3:07 ahead" reads better than "187s ahead".
    ///
    /// The seconds form goes through `Duration`'s own formatting rather than appending an "s". A
    /// hardcoded suffix is a unit abbreviation in one language, and the unit is the part that
    /// changes — the number is not.
    static func gapText(_ seconds: Int) -> String {
        seconds < 60
            ? Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .narrow))
            : text(TimeInterval(seconds))
    }
}
