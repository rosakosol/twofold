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
                // Loops first, so letters sit on top of their own outline rather than under it.
                ForEach(Array(play.foundPlacements.enumerated()), id: \.element) { position, placement in
                    loop(around: placement, cell: cell, colorIndex: position)
                }

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

    /// The loop colours, cycled by find order.
    ///
    /// Words cross — the generator allows it and wants it, because a grid where no two words touch
    /// is a grid where finding one tells you nothing. A single colour made a crossing unreadable:
    /// two loops in the same ink over a shared letter look like one bent shape. Different hues per
    /// word is how a paper word search stays legible, and it is why these are drawn as outlines
    /// rather than fills in the first place — a filled cell can only belong to one word.
    ///
    /// Chosen to stay apart from `selectionFill` (the live drag) and from each other at the width
    /// a loop is drawn, and defined here rather than pulled from `Theme` for the same reason the
    /// Word Guess tiles are: this is the game's own vocabulary, not the app's palette.
    private static let loopColors: [Color] = [
        Color(light: "2E7D32", dark: "6BBF70"),
        Color(light: "AD5A1F", dark: "E09A5A"),
        Color(light: "7B3FA0", dark: "BE8FDC"),
        Color(light: "1F7A8C", dark: "6FC7D6"),
        Color(light: "B03050", dark: "E58098"),
        Color(light: "5C6BC0", dark: "97A4E8"),
    ]

    /// A stadium drawn around one found word, the way a pencil circles it.
    ///
    /// Built by stroking the line from the first letter's centre to the last letter's centre with a
    /// round cap — that gives the stadium *shape* — and then taking `strokedPath` of it, which is
    /// that shape's outline. Stroking the outline is what makes it a loop rather than a bar: a
    /// filled stadium would cover the letters it is meant to be pointing at.
    private func loop(around placement: WordSearchPlacement, cell: CGFloat, colorIndex: Int) -> some View {
        let cells = placement.cells(size: size)
        let color = Self.loopColors[colorIndex % Self.loopColors.count]

        return Path { path in
            guard let first = cells.first, let last = cells.last else { return }
            path.move(to: center(of: first, cell: cell))
            // A single-letter word would give a zero-length line, which strokes to nothing — the
            // `addLine` to the same point still produces a round dot at that cap width.
            path.addLine(to: center(of: last, cell: cell))
        }
        .strokedPath(StrokeStyle(lineWidth: cell * 0.78, lineCap: .round))
        .stroke(color, lineWidth: max(1.5, cell * 0.075))
        .allowsHitTesting(false)
    }

    private func center(of index: Int, cell: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(index % size) + 0.5) * cell,
            y: (CGFloat(index / size) + 0.5) * cell
        )
    }

    private func letter(at index: Int, isFound: Bool, isSelected: Bool, side: CGFloat) -> some View {
        Text(String(play.puzzle[index]))
            .font(.system(size: side * 0.42, weight: isFound ? .semibold : .medium, design: .rounded))
            // Found letters keep the grid's own ink now. They used to go green, which was a second
            // way of saying what the loop already says — and on a letter two crossing words share,
            // one colour could only ever be right about one of them.
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .frame(width: side, height: side)
            .background {
                // Only the live drag fills a cell. A finger crossing words already found should
                // still show what it is covering right now, so this wins over any loop beneath it.
                if isSelected {
                    RoundedRectangle(cornerRadius: side * 0.25).fill(Self.selectionFill)
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
