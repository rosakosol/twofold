//
//  ConnectFourBoardView.swift
//  Twofold
//
//  The board: seven columns of six slots, tapped by column rather than by cell.
//
//  By column because that is the move. Gravity decides the row, so a cell-sized tap target would be
//  offering a choice the game does not have — and the empty slots above the pile are the easiest
//  part of a column to hit.
//

import SwiftUI

struct ConnectFourBoardView: View {
    let board: ConnectFourBoard
    /// Which disc is this player's, so their own colour is the one named "you" on screen.
    let myDisc: ConnectFourBoard.Disc?
    /// Columns still open, and whether tapping does anything at all.
    let isInteractive: Bool
    let onDrop: (Int) -> Void
    /// The column the most recent disc went into, and how many moves have been played.
    ///
    /// Together they pick out the one disc that should fall. The column alone is not enough: the
    /// board is rebuilt from the whole move list on every refresh, so without a move count to
    /// change with it, a disc would either animate again on an unrelated reload or never animate
    /// twice in the same column.
    var lastDropColumn: Int?
    var moveCount: Int = 0

    /// The four that won it, dimmed against everything else once there is a winner.
    private var winningCells: Set<Int> {
        Set(board.winningLine()?.cells ?? [])
    }

    var body: some View {
        GeometryReader { proxy in
            let slot = proxy.size.width / CGFloat(ConnectFourBoard.columns)
            HStack(spacing: 0) {
                ForEach(0..<ConnectFourBoard.columns, id: \.self) { column in
                    columnView(column, slot: slot)
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: slot * 0.3))
        }
        .aspectRatio(CGFloat(ConnectFourBoard.columns) / CGFloat(ConnectFourBoard.rows), contentMode: .fit)
    }

    private func columnView(_ column: Int, slot: CGFloat) -> some View {
        let isOpen = board.landingRow(in: column) != nil
        return VStack(spacing: 0) {
            ForEach(0..<ConnectFourBoard.rows, id: \.self) { row in
                disc(at: row, column: column, slot: slot)
            }
        }
        // The whole column is the tap target, including the empty slots above the pile — which is
        // where a finger naturally goes when aiming at a column rather than a square.
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive, isOpen else { return }
            onDrop(column)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(columnLabel(column))
        .accessibilityAddTraits(isInteractive && isOpen ? .isButton : [])
        .accessibilityHint(isInteractive && isOpen ? "Drops your disc here" : "")
    }

    private func disc(at row: Int, column: Int, slot: CGFloat) -> some View {
        let index = row * ConnectFourBoard.columns + column
        let occupant = board[row, column]
        let isWinning = winningCells.contains(index)
        let hasWinner = !winningCells.isEmpty

        // A disc lands on top of whatever is already in its column, so the newest one in a column
        // is always the highest occupied cell in it. That is cheaper and more robust than tracking
        // a row alongside the column, and it cannot disagree with the board it is drawn from.
        let isNewest = occupant != nil
            && column == lastDropColumn
            && row == topmostOccupiedRow(in: column)

        return DroppingDisc(
            color: fill(for: occupant),
            inset: slot * 0.09,
            // From above the board's top edge, so it enters the frame rather than appearing inside
            // it — the distance grows with how far down the disc ends up.
            fallHeight: CGFloat(row + 1) * slot,
            animates: isNewest
        )
        // A fresh identity for the falling disc each move, which is what re-runs its `onAppear`.
        // Every other cell keeps a stable one so nothing else is rebuilt.
        .id("\(index)-\(isNewest ? moveCount : 0)")
            .frame(width: slot, height: slot)
            // Once the game is won, everything outside the line steps back so the four that did it
            // read as the answer to "why".
            .opacity(hasWinner && !isWinning && occupant != nil ? 0.45 : 1)
            .overlay {
                if isWinning {
                    Circle()
                        .strokeBorder(Theme.ink.opacity(0.55), lineWidth: 2)
                        .padding(slot * 0.09)
                }
            }
    }

    /// The highest occupied row in a column, or nil if it is empty. Row 0 is the top.
    private func topmostOccupiedRow(in column: Int) -> Int? {
        (0..<ConnectFourBoard.rows).first { board[$0, column] != nil }
    }

    private func fill(for disc: ConnectFourBoard.Disc?) -> Color {
        switch disc {
        case .first: Self.firstColor
        case .second: Self.secondColor
        // The empty slot is a hole in the board, so it shows the screen behind rather than a
        // lighter disc — a pale filled circle reads as a third player's piece.
        case nil: Theme.subtleInk.opacity(0.12)
        }
    }

    /// Red and yellow, because that is what this game is. Both are fixed rather than theme tokens:
    /// they are the two players, and a colour that shifts between light and dark mode would make
    /// "you are the red one" a statement that stops being true.
    static let firstColor = Color(light: "D9534F", dark: "E2635F")
    static let secondColor = Color(light: "E8B33C", dark: "E9BC55")

    private func columnLabel(_ column: Int) -> String {
        let occupied = (0..<ConnectFourBoard.rows).compactMap { board[$0, column] }
        guard !occupied.isEmpty else { return "Column \(column + 1), empty" }
        let mine = occupied.count { $0 == myDisc }
        let theirs = occupied.count - mine
        return "Column \(column + 1), \(occupied.count) discs, \(mine) yours and \(theirs) theirs"
    }
}

#Preview("Mid game") {
    ConnectFourBoardView(
        board: ConnectFourBoard(droppedColumns: [3, 3, 4, 2, 4, 4, 5]),
        myDisc: .first,
        isInteractive: true,
        onDrop: { _ in }
    )
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("Won") {
    ConnectFourBoardView(
        board: ConnectFourBoard(droppedColumns: [0, 0, 1, 1, 2, 2, 3]),
        myDisc: .first,
        isInteractive: false,
        onDrop: { _ in }
    )
    .padding()
    .background(Theme.backgroundGradient)
}

/// One disc, which falls into place if it is the one that was just played.
///
/// Its own view because the animation needs state of its own: the offset has to be non-zero for a
/// frame before it animates to zero, and a `@State` flag flipped in `onAppear` is what gives it
/// that frame. The caller re-creates this view per move (see the `.id` above), which is what makes
/// `onAppear` fire again for a second disc in the same column.
private struct DroppingDisc: View {
    let color: Color
    let inset: CGFloat
    let fallHeight: CGFloat
    let animates: Bool

    @State private var landed = false

    var body: some View {
        Circle()
            .fill(color)
            .padding(inset)
            .offset(y: landed || !animates ? 0 : -fallHeight)
            .onAppear {
                guard animates else { return }
                // Overshoots slightly and settles, the way a real counter drops into a slot and
                // knocks against the one below it. A plain ease would read as the disc being
                // lowered rather than dropped.
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { landed = true }
            }
    }
}
