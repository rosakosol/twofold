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
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            // Square, and driven by the width it is given — so the board fits the phone rather than
            // the phone having to fit a fixed tile size.
            .aspectRatio(1, contentMode: .fit)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 2))
    }
}

#Preview("Mid board") {
    var state = WordGuessPlayState(answer: "roast")
    _ = state.commit("crane")
    _ = state.commit("solid")
    return WordGuessBoardView(play: state, draft: "TRO", isDraftRejected: false)
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Rejected guess") {
    WordGuessBoardView(play: WordGuessPlayState(answer: "roast"), draft: "ZZZZZ", isDraftRejected: true)
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Solved") {
    var state = WordGuessPlayState(answer: "roast")
    _ = state.commit("crane")
    _ = state.commit("toads")
    _ = state.commit("roast")
    return WordGuessBoardView(play: state, draft: "", isDraftRejected: false)
        .padding()
        .background(Theme.backgroundGradient)
}
