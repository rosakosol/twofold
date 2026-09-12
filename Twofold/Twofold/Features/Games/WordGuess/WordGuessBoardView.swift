//
//  WordGuessBoardView.swift
//  Twofold
//
//  Six rows of five tiles.
//
//  The colours are defined here rather than in `Theme` because they are not the app's palette —
//  they are this game's alphabet. Green/amber/grey is the convention every player of this kind of
//  game already reads fluently, and substituting Twofold's own colours would make a familiar board
//  need learning again.
//
//  They are still theme-aware, because a board that keeps light-mode colours in dark mode is the
//  brightest thing on a dark screen.
//

import SwiftUI

extension WordGuessMark {
    /// The tile's fill. Deliberately saturated: this is the only thing on the screen carrying
    /// information, and a muted version of it would be harder to read at a glance than the letter.
    var tileColor: Color {
        switch self {
        case .correct: Color(light: "5FA463", dark: "5C9E60")
        case .present: Color(light: "C9AF3E", dark: "B79B33")
        case .absent: Color(light: "8B939B", dark: "4A535C")
        }
    }

    /// White on all three, in both themes. The fills above are chosen dark enough to carry it,
    /// which is what keeps one letter style rather than three.
    var tileTextColor: Color { .white }

    /// What a screen reader says for this tile. The colours are the entire game state, so a board
    /// that reads out only its letters tells a VoiceOver user nothing about how they are doing.
    var accessibilityDescription: String {
        switch self {
        case .correct: "correct"
        case .present: "in the word, wrong place"
        case .absent: "not in the word"
        }
    }
}

struct WordGuessBoardView: View {
    let play: WordGuessPlayState
    /// What is typed but not committed, shown on the first empty row.
    let draft: String
    /// Set when the last guess bounced, so the row can flag itself rather than only relying on a
    /// message elsewhere on the screen.
    let isDraftRejected: Bool
    /// The edge length of every tile, in points. Passed in rather than derived here, because the
    /// caller is the only one that knows how much height is left once the keyboard has taken its
    /// share — see `tileSide(forWidth:)` and `boardHeight(forTileSide:)` for the two halves of it.
    let tileSide: CGFloat

    /// The largest square tile that fits `width` once the four gaps between five tiles are taken
    /// out of it.
    static func tileSide(forWidth width: CGFloat) -> CGFloat {
        let gaps = Theme.Spacing.xs * CGFloat(WordGuessWords.length - 1)
        return max(0, (width - gaps) / CGFloat(WordGuessWords.length))
    }

    /// The largest square tile that fits `height` once the five gaps between six rows are taken
    /// out of it. The counterpart to `tileSide(forWidth:)` — a caller takes the smaller of the two
    /// so the board fits both ways.
    static func tileSide(forHeight height: CGFloat) -> CGFloat {
        let gaps = Theme.Spacing.xs * CGFloat(WordGuessWords.maxGuesses - 1)
        return max(0, (height - gaps) / CGFloat(WordGuessWords.maxGuesses))
    }

    /// What the board measures with tiles that size — six rows and the five gaps between them.
    static func boardHeight(forTileSide side: CGFloat) -> CGFloat {
        side * CGFloat(WordGuessWords.maxGuesses)
            + Theme.Spacing.xs * CGFloat(WordGuessWords.maxGuesses - 1)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<WordGuessWords.maxGuesses, id: \.self) { row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Int) -> some View {
        if row < play.guesses.count {
            committedRow(row)
        } else if row == play.guesses.count {
            draftRow
        } else {
            emptyRow
        }
    }

    private func committedRow(_ row: Int) -> some View {
        let word = Array(play.guesses[row].uppercased())
        let marks = play.marks(forGuessAt: row)
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<WordGuessWords.length, id: \.self) { column in
                let mark = marks.indices.contains(column) ? marks[column] : .absent
                tile(
                    letter: word.indices.contains(column) ? word[column] : " ",
                    fill: mark.tileColor,
                    textColor: mark.tileTextColor,
                    border: .clear
                )
                .accessibilityLabel("\(String(word[column])), \(mark.accessibilityDescription)")
            }
        }
        // One element per row, or VoiceOver makes the player swipe through thirty tiles to read a
        // board they can see at a glance.
        .accessibilityElement(children: .combine)
    }

    private var draftRow: some View {
        let letters = Array(draft.uppercased())
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<WordGuessWords.length, id: \.self) { column in
                tile(
                    letter: letters.indices.contains(column) ? letters[column] : " ",
                    fill: .clear,
                    textColor: Theme.ink,
                    // Red only while the guess is being refused. A permanently coloured active row
                    // would read as a verdict on letters nobody has submitted yet.
                    border: isDraftRejected ? Theme.heartRed
                        : letters.indices.contains(column) ? Theme.ink.opacity(0.45)
                        : Theme.subtleInk.opacity(0.3)
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(draft.isEmpty ? "Your guess, empty" : "Your guess so far, \(Array(draft.uppercased()).map(String.init).joined(separator: " "))")
    }

    private var emptyRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<WordGuessWords.length, id: \.self) { _ in
                tile(letter: " ", fill: .clear, textColor: Theme.ink, border: Theme.subtleInk.opacity(0.3))
            }
        }
        .accessibilityHidden(true)
    }

    private func tile(letter: Character, fill: Color, textColor: Color, border: Color) -> some View {
        Text(String(letter))
            .font(.title.weight(.bold))
            // The tile is a fixed square now, so a letter at an accessibility text size has to give
            // way rather than stretch it back into a rectangle.
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(textColor)
            // Stated outright, both dimensions. This used to be `.frame(maxWidth: .infinity)`
            // followed by `.aspectRatio(1, contentMode: .fit)`, which looks like it makes a square
            // and does not: `aspectRatio` proposes a square to its child, but that frame only
            // stretches horizontally, so it answered with the *text's* line height and the tile
            // came out a wide, short rectangle. Asking for the size directly has no such gap
            // between what it reads like and what it does.
            .frame(width: tileSide, height: tileSide)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 2))
    }
}

#Preview("Mid board") {
    var state = WordGuessPlayState(answer: "roast")
    _ = state.commit("crane")
    _ = state.commit("solid")
    return WordGuessBoardView(play: state, draft: "TRO", isDraftRejected: false, tileSide: 64)
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Rejected guess") {
    WordGuessBoardView(play: WordGuessPlayState(answer: "roast"), draft: "ZZZZZ", isDraftRejected: true, tileSide: 64)
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Solved") {
    var state = WordGuessPlayState(answer: "roast")
    _ = state.commit("crane")
    _ = state.commit("toads")
    _ = state.commit("roast")
    return WordGuessBoardView(play: state, draft: "", isDraftRejected: false, tileSide: 64)
        .padding()
        .background(Theme.backgroundGradient)
}
