//
//  SudokuBoardView.swift
//  Twofold
//
//  The grid.
//
//  Laid out by hand from a measured side length rather than with `LazyVGrid`, because a sudoku is
//  the one layout where a rounding error is visible: cells that differ by half a point leave the
//  box rules looking crooked, and the thick lines have to land exactly on a cell boundary. One
//  `side / 9` and an offset per cell keeps every line where the arithmetic says it goes.
//

import SwiftUI

struct SudokuBoardView: View {
    let puzzle: SudokuGrid
    let play: SudokuPlayState
    let conflicts: Set<Int>
    /// Cells a "check" found to be wrong. Distinct from `conflicts`, which only knows about a digit
    /// repeated against a peer — a wrong digit breaking no rule yet is invisible to that, and is
    /// the one worth telling someone about.
    var mistakes: Set<Int> = []
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cell = side / 9

            ZStack(alignment: .topLeading) {
                ForEach(0..<81, id: \.self) { index in
                    cellView(index, size: cell)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(index % 9) * cell, y: CGFloat(index / 9) * cell)
                }
                rules(side: side, cell: cell)
            }
            .frame(width: side, height: side)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Cells

    @ViewBuilder
    private func cellView(_ index: Int, size: CGFloat) -> some View {
        let value = play[index]
        let isGiven = puzzle[index] != 0

        ZStack {
            highlight(for: index)
            // Drawn over the selection wash rather than folded into it: a checked mistake is a
            // statement about the cell, and it has to survive the cell being selected — which is
            // the first thing anyone does on being told one of their digits is wrong.
            if mistakes.contains(index) {
                Theme.heartRed.opacity(0.22)
            }
            if value != 0 {
                Text(String(value))
                    .font(.system(size: size * 0.55, weight: isGiven ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(colour(index: index, isGiven: isGiven))
                    // Digits vary in width; a sudoku reads as a grid only if they all sit on the
                    // same centre.
                    .monospacedDigit()
            } else {
                notesView(index, size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(index) }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(index))
        .accessibilityAddTraits(selected == index ? [.isSelected, .isButton] : .isButton)
    }

    private func colour(index: Int, isGiven: Bool) -> Color {
        if conflicts.contains(index) || mistakes.contains(index) { return Theme.heartRedText }
        // The puzzle's own numbers and the player's are deliberately different weights *and*
        // colours: knowing at a glance which cells are yours to change is most of playing.
        return isGiven ? Theme.ink : Theme.skyBlueText
    }

    @ViewBuilder
    private func highlight(for index: Int) -> some View {
        if selected == index {
            Theme.skyBlue.opacity(0.28)
        } else if let selected {
            let value = play[selected]
            if value != 0 && play[index] == value {
                // Everywhere this digit already sits — the single most useful hint a board can
                // give without solving anything for you.
                Theme.skyBlue.opacity(0.18)
            } else if SudokuPlayState.peers(of: selected).contains(index) {
                Theme.skyBlue.opacity(0.07)
            } else {
                Color.clear
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func notesView(_ index: Int, size: CGFloat) -> some View {
        let marks = (UInt8(1)...UInt8(9)).filter { play.note($0, at: index) }
        if !marks.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            let value = UInt8(row * 3 + column + 1)
                            Text(play.note(value, at: index) ? String(value) : " ")
                                .font(.system(size: size * 0.22, design: .rounded))
                                .foregroundStyle(Theme.subtleInk)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .padding(size * 0.06)
        }
    }

    // MARK: - Rules

    /// Thin lines between cells, thick ones between boxes and around the edge — the only thing that
    /// makes a 9x9 grid readable as nine 3x3s.
    private func rules(side: CGFloat, cell: CGFloat) -> some View {
        Canvas { context, _ in
            for line in 0...9 {
                let position = CGFloat(line) * cell
                let isBox = line % 3 == 0
                let width: CGFloat = isBox ? 2 : 0.5
                let shade = isBox ? 0.45 : 0.18

                var vertical = Path()
                vertical.move(to: CGPoint(x: position, y: 0))
                vertical.addLine(to: CGPoint(x: position, y: side))
                context.stroke(vertical, with: .color(Theme.ink.opacity(shade)), lineWidth: width)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: position))
                horizontal.addLine(to: CGPoint(x: side, y: position))
                context.stroke(horizontal, with: .color(Theme.ink.opacity(shade)), lineWidth: width)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    // MARK: - VoiceOver

    private func accessibilityLabel(_ index: Int) -> String {
        let position = "Row \(index / 9 + 1), column \(index % 9 + 1)"
        let value = play[index]
        if value != 0 {
            let ownership = puzzle[index] != 0 ? "given" : "your answer"
            // Two different claims, and the stronger one wins: a conflict says this digit repeats
            // somewhere, a checked mistake says it is simply not the answer.
            let fault = mistakes.contains(index) ? ", wrong"
                : conflicts.contains(index) ? ", conflicts with another cell" : ""
            return "\(position), \(value), \(ownership)\(fault)"
        }
        let marks = (UInt8(1)...UInt8(9)).filter { play.note($0, at: index) }
        if marks.isEmpty { return "\(position), empty" }
        return "\(position), empty, notes \(marks.map(String.init).joined(separator: ", "))"
    }
}
