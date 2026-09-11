//
//  WordSearchGridView.swift
//  Twofold
//
//  A hundred letters, and a finger dragged across them.
//
//  The drag is one gesture over the whole grid rather than a gesture per cell. Per-cell gestures
//  only fire for the cell the touch *started* in, so a drag would select one letter and then report
//  nothing for the rest of the run; the grid has to do the hit-testing itself, which is why the
//  cell size is computed here rather than left to the layout.
//

import SwiftUI

struct WordSearchGridView: View {
    let play: WordSearchPlayState
    /// Cells under the finger right now, from the store.
    let selection: [Int]
    let onBegin: (Int) -> Void
    let onExtend: (Int) -> Void
    let onEnd: () -> Void

    private var size: Int { WordSearchPuzzle.size }

    var body: some View {
        GeometryReader { proxy in
            let cell = proxy.size.width / CGFloat(size)
            let found = play.foundCells
            let selected = Set(selection)

            ZStack(alignment: .topLeading) {
                ForEach(0..<(size * size), id: \.self) { index in
                    let row = index / size
                    let column = index % size
                    letter(
                        at: index,
                        isFound: found.contains(index),
                        isSelected: selected.contains(index),
                        side: cell
                    )
                    .position(
                        x: (CGFloat(column) + 0.5) * cell,
                        y: (CGFloat(row) + 0.5) * cell
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` so a single tap registers as a begin — otherwise the first
                // letter of a word only lights up once the finger has already moved off it.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let index = cellIndex(at: value.location, cell: cell) else { return }
                        if selection.isEmpty {
                            onBegin(index)
                        } else {
                            onExtend(index)
                        }
                    }
                    .onEnded { _ in onEnd() }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        // The grid is a drawing of a puzzle; the word list beside it is what VoiceOver can actually
        // work with, and a hundred unlabelled letters would be a hundred swipes to reach it.
        .accessibilityHidden(true)
    }

    private func cellIndex(at point: CGPoint, cell: CGFloat) -> Int? {
        guard cell > 0 else { return nil }
        let column = Int(point.x / cell)
        let row = Int(point.y / cell)
        guard (0..<size).contains(column), (0..<size).contains(row) else { return nil }
        return row * size + column
    }

    /// The live selection's fill, paired with the white it has to carry.
    ///
    /// Not `Theme.skyBlue`: that token is a *light* blue in dark mode — correct for a tint on a
    /// dark ground, wrong as a fill behind white letters, which came out barely legible. This stays
    /// dark enough for white in both themes, which is what a fill-plus-text pair has to be.
    private static let selectionFill = Color(light: "3080C0", dark: "2F6FA8")

    private func letter(at index: Int, isFound: Bool, isSelected: Bool, side: CGFloat) -> some View {
        Text(String(play.puzzle[index]))
            .font(.system(size: side * 0.42, weight: isFound ? .bold : .medium, design: .rounded))
            .foregroundStyle(isSelected ? .white : isFound ? Theme.leafGreenText : Theme.ink)
            .frame(width: side, height: side)
            .background {
                if isSelected {
                    // The live selection wins over the found highlight. A finger dragging across
                    // words already found should still show what it is currently covering.
                    RoundedRectangle(cornerRadius: side * 0.25).fill(Self.selectionFill)
                } else if isFound {
                    RoundedRectangle(cornerRadius: side * 0.25).fill(Theme.leafGreen.opacity(0.22))
                }
            }
    }
}

#Preview("Part way through") {
    let puzzle = WordSearchGenerator.puzzle(seed: 3, theme: .travel)
    var state = WordSearchPlayState(puzzle: puzzle)
    state.find(cells: puzzle.placements[0].cells(size: WordSearchPuzzle.size))
    state.find(cells: puzzle.placements[1].cells(size: WordSearchPuzzle.size))
    return WordSearchGridView(
        play: state,
        selection: puzzle.placements[2].cells(size: WordSearchPuzzle.size),
        onBegin: { _ in }, onExtend: { _ in }, onEnd: {}
    )
    .padding()
    .background(Theme.backgroundGradient)
}
