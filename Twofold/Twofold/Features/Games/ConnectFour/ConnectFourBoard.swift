//
//  ConnectFourBoard.swift
//  Twofold
//
//  Seven columns, six rows, and the rules for what lands where.
//
//  ---------------------------------------------------------------------------
//  There are two implementations of this, deliberately
//  ---------------------------------------------------------------------------
//
//  `private.connect_four_board` and `private.connect_four_winner` do the same thing in SQL, and
//  that duplication is chosen rather than accidental. The server's copy is the one that *decides*:
//  it ends the game, records who won, and is the only one a modified client cannot argue with. This
//  copy exists because the board has to be drawn, the next move previewed, and a full column greyed
//  out before anybody taps it — none of which can wait for a round trip.
//
//  The risk in two copies is that they disagree. What makes that survivable is which one is
//  authoritative: if this one is wrong, a player sees a board that briefly contradicts the server
//  and is corrected on the next move. If the server's were wrong, the game would end incorrectly
//  and there would be no correcting it, because the move log is append-only.
//
//  `ConnectFourBoardTests` checks this one against the same cases the pgTAP suite checks the other
//  against — the same four directions, the same wrap-around, the same broken run.
//

import Foundation

struct ConnectFourBoard: Equatable {
    static let columns = 7
    static let rows = 6

    /// Which player's disc is in each cell, row-major with row 0 at the top. nil is empty.
    ///
    /// `.first` is whoever moved first — the session's initiator — rather than a colour or a
    /// person. The board does not know who that is, and does not need to.
    enum Disc: Equatable {
        case first
        case second
    }

    private(set) var cells: [Disc?]

    init() {
        cells = Array(repeating: nil, count: Self.columns * Self.rows)
    }

    /// Replays a list of dropped columns, alternating from the first player.
    ///
    /// Takes columns rather than moves-with-players for the same reason the SQL derives the player
    /// from the move count: turns strictly alternate, so storing who played each one would be a
    /// second copy of a fact the order already carries — and the copy that can disagree is the one
    /// that eventually does.
    init(droppedColumns: [Int]) {
        self.init()
        for (index, column) in droppedColumns.enumerated() {
            drop(in: column, as: index % 2 == 0 ? .first : .second)
        }
    }

    subscript(row: Int, column: Int) -> Disc? {
        guard (0..<Self.rows).contains(row), (0..<Self.columns).contains(column) else { return nil }
        return cells[row * Self.columns + column]
    }

    /// The row a disc dropped into this column would land in, or nil if it is full.
    ///
    /// Also the "can I play here" check, which is why it returns the row rather than a bool: the
    /// board needs the landing square to animate the drop and to preview the move.
    func landingRow(in column: Int) -> Int? {
        guard (0..<Self.columns).contains(column) else { return nil }
        // Gravity: the lowest empty cell, searched from the bottom up.
        for row in stride(from: Self.rows - 1, through: 0, by: -1) where self[row, column] == nil {
            return row
        }
        return nil
    }

    var playableColumns: [Int] {
        (0..<Self.columns).filter { landingRow(in: $0) != nil }
    }

    var isFull: Bool { playableColumns.isEmpty }

    @discardableResult
    mutating func drop(in column: Int, as disc: Disc) -> Int? {
        guard let row = landingRow(in: column) else { return nil }
        cells[row * Self.columns + column] = disc
        return row
    }

    // MARK: - Winning

    /// The four cells that won it, if somebody has four in a row.
    ///
    /// Returns the line rather than just the winner so the board can highlight it. A result screen
    /// that says who won without showing *why* leaves the loser hunting the board for it.
    func winningLine() -> (disc: Disc, cells: [Int])? {
        // Right, down, down-right, down-left. The other four directions are these same lines walked
        // backwards, so checking them too would only find each win twice.
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

        for row in 0..<Self.rows {
            for column in 0..<Self.columns {
                guard let disc = self[row, column] else { continue }
                for (rowStep, columnStep) in directions {
                    var line = [row * Self.columns + column]
                    var r = row, c = column
                    while line.count < 4 {
                        r += rowStep
                        c += columnStep
                        // The bounds check is what stops a run walking off the end of one row and
                        // continuing along the start of the next — which in a flat array looks
                        // exactly like a win nobody made.
                        guard (0..<Self.rows).contains(r), (0..<Self.columns).contains(c),
                              self[r, c] == disc else { break }
                        line.append(r * Self.columns + c)
                    }
                    if line.count == 4 { return (disc, line) }
                }
            }
        }
        return nil
    }

    var winner: Disc? { winningLine()?.disc }

    /// Nobody won and there is nowhere left to play.
    var isDraw: Bool { winner == nil && isFull }

    var isFinished: Bool { winner != nil || isFull }
}
