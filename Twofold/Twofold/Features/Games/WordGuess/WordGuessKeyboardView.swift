//
//  WordGuessKeyboardView.swift
//  Twofold
//
//  The game's own keyboard, rather than the system one.
//
//  Not a stylistic choice. The keys carry state — a letter already ruled out is greyed, one known
//  to be in the word is coloured — and that running record is half of how the game is played. The
//  system keyboard cannot show it, would offer autocorrect and emoji on a five-letter grid, and
//  would take a third of the screen the board needs.
//

import SwiftUI

struct WordGuessKeyboardView: View {
    /// What each letter is known to be, from every guess so far.
    let marks: [Character: WordGuessMark]
    /// False once the board is finished, so the keys go quiet rather than accepting taps that do
    /// nothing.
    let isEnabled: Bool
    /// Greyed until the row is full — there is nothing to submit before that, and a live Enter
    /// invites a tap that can only be refused.
    let canSubmit: Bool
    let onLetter: (Character) -> Void
    let onBackspace: () -> Void
    let onSubmit: () -> Void

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private static let keySpacing: CGFloat = 4
    private static let keyHeight: CGFloat = 46
    /// The top row's ten keys set the unit every other key is measured in. Without this the bottom
    /// row's seven letters simply divide whatever ENTER and ⌫ leave them, and come out visibly
    /// fatter than the letters directly above — which reads as a rendering bug rather than a
    /// layout.
    private static let unitsPerRow: CGFloat = 10
    /// ENTER needs its word to fit, so it takes one and a half keys. ⌫ matches it, or the bottom
    /// row is lopsided.
    private static let actionKeyUnits: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let unit = (proxy.size.width - Self.keySpacing * (Self.unitsPerRow - 1)) / Self.unitsPerRow
            let action = unit * Self.actionKeyUnits + Self.keySpacing * (Self.actionKeyUnits - 1)

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(Self.rows.indices, id: \.self) { index in
                    HStack(spacing: Self.keySpacing) {
                        // The middle row is one key short of the top. Half-key margins on each side
                        // sit it centred under the row above, the way every keyboard of this kind
                        // is laid out.
                        if index == 1 { Spacer(minLength: 0).frame(width: (unit + Self.keySpacing) / 2) }
                        if index == 2 {
                            actionKey("ENTER", width: action, enabled: isEnabled && canSubmit, action: onSubmit)
                        }

                        ForEach(Array(Self.rows[index]), id: \.self) { letter in
                            letterKey(letter, width: unit)
                        }

                        if index == 2 {
                            actionKey("⌫", width: action, enabled: isEnabled, action: onBackspace)
                                .accessibilityLabel("Delete")
                        }
                        if index == 1 { Spacer(minLength: 0).frame(width: (unit + Self.keySpacing) / 2) }
                    }
                }
            }
        }
        // A `GeometryReader` fills whatever it is offered, so the keyboard has to state its own
        // height or it takes the rest of the screen and pushes the board off the top.
        .frame(height: Self.keyHeight * 3 + Theme.Spacing.xs * 2)
    }

    private func letterKey(_ letter: Character, width: CGFloat) -> some View {
        let mark = marks[letter]
        return Button {
            onLetter(letter)
        } label: {
            Text(String(letter).uppercased())
                .font(.callout.weight(.semibold))
                .foregroundStyle(mark?.tileTextColor ?? Theme.ink)
                .frame(width: width, height: Self.keyHeight)
                .background(mark?.tileColor ?? Theme.cardBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // A greyed-out key is still tappable, deliberately: ruling a letter out does not stop it
        // being part of a word you want to try, and a keyboard that removes keys is a keyboard
        // that loses guesses to mis-taps.
        .accessibilityLabel(mark.map { "\(letter), \($0.accessibilityDescription)" } ?? String(letter))
    }

    private func actionKey(_ title: String, width: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(enabled ? Theme.ink : Theme.subtleInk)
                .frame(width: width, height: Self.keyHeight)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview {
    WordGuessKeyboardView(
        marks: WordGuessEvaluation.keyboardMarks(guesses: ["crane", "solid"], answer: "roast"),
        isEnabled: true,
        canSubmit: true,
        onLetter: { _ in },
        onBackspace: {},
        onSubmit: {}
    )
    .padding()
    .background(Theme.backgroundGradient)
}
