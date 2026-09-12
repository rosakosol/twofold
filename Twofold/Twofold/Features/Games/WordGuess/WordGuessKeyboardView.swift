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
    let onLetter: (Character) -> Void
    let onBackspace: () -> Void
    /// How tall each key is. The caller decides, because only it knows how much screen is left
    /// after the board — a keyboard sized in isolation either leaves the bottom of a big phone
    /// empty or crowds a small one. `defaultKeyHeight` is what it was when this was fixed, and is
    /// still the floor the caller clamps to.
    var keyHeight: CGFloat = WordGuessKeyboardView.defaultKeyHeight

    static let defaultKeyHeight: CGFloat = 46

    /// The height this keyboard occupies for a given key height — so a caller can subtract it from
    /// the screen before deciding what is left for the board, without re-deriving the row maths.
    static func height(forKeyHeight keyHeight: CGFloat) -> CGFloat {
        keyHeight * 3 + Theme.Spacing.xs * 2
    }

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private static let keySpacing: CGFloat = 4
    /// The top row's ten keys set the unit every other key is measured in. Without this the bottom
    /// row's seven letters simply divide whatever ENTER and ⌫ leave them, and come out visibly
    /// fatter than the letters directly above — which reads as a rendering bug rather than a
    /// layout.
    private static let unitsPerRow: CGFloat = 10
    /// ⌫ takes one and a half keys, and an equal half-key sits opposite it so the bottom row stays
    /// centred under the two above.
    ///
    /// ENTER used to live on the other side. A full row now submits itself the moment its fifth
    /// letter lands (see `WordGuessGameStore.type`), so ENTER could never be anything but greyed
    /// out — a key whose only state is "not available" is worse than no key, and removing it gives
    /// the letters the room instead.
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
                        // The bottom row is centred the same way the middle one is, now that ENTER
                        // is gone and only backspace sits beside the letters.
                        if index == 2 { Spacer(minLength: 0).frame(width: (action + Self.keySpacing) / 2) }

                        ForEach(Array(Self.rows[index]), id: \.self) { letter in
                            letterKey(letter, width: unit)
                        }

                        if index == 2 { backspaceKey(width: action) }
                        if index == 1 { Spacer(minLength: 0).frame(width: (unit + Self.keySpacing) / 2) }
                    }
                }
            }
        }
        // A `GeometryReader` fills whatever it is offered, so the keyboard has to state its own
        // height or it takes the rest of the screen and pushes the board off the top.
        .frame(height: Self.height(forKeyHeight: keyHeight))
    }

    /// Glyph size for a key of this width.
    ///
    /// The letters were a fixed `.callout` — about 16pt — from back when a key was 46pt tall and
    /// roughly square. Keys now grow with the screen, and a 16pt letter adrift in a 34x70 key is
    /// what "the keyboard is too small" actually looks like: the keys were already large, the
    /// writing on them was not. Scaled off width because width is the binding dimension; the
    /// system keyboard's own letters sit at a similar fraction of their key.
    private func glyphSize(forKeyWidth width: CGFloat) -> CGFloat { max(13, width * 0.62) }

    /// Corners scale too. A 5pt radius reads as sharp on a 46pt key and as an accident on a 70pt
    /// one, because the curve stops being a noticeable share of the edge.
    private func cornerRadius(forKeyWidth width: CGFloat) -> CGFloat { max(5, min(width, keyHeight) * 0.22) }

    private func letterKey(_ letter: Character, width: CGFloat) -> some View {
        let mark = marks[letter]
        let radius = cornerRadius(forKeyWidth: width)
        return Button {
            onLetter(letter)
        } label: {
            Text(String(letter).uppercased())
                .font(.system(size: glyphSize(forKeyWidth: width), weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(mark?.tileTextColor ?? Theme.ink)
                .frame(width: width, height: keyHeight)
                .background(mark?.tileColor ?? Theme.cardBackground, in: RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(KeyPressStyle(cornerRadius: radius))
        .disabled(!isEnabled)
        // A greyed-out key is still tappable, deliberately: ruling a letter out does not stop it
        // being part of a word you want to try, and a keyboard that removes keys is a keyboard
        // that loses guesses to mis-taps.
        .accessibilityLabel(mark.map { "\(letter), \($0.accessibilityDescription)" } ?? String(letter))
    }

    /// Backspace, as a symbol rather than the "⌫" character.
    ///
    /// That character was set in `.caption2` — 11pt — which on a key this size was a smudge. It is
    /// also a glyph whose rendering is at the mercy of whatever font has it, where
    /// `delete.backward` is drawn by SF Symbols at whatever weight and size it is asked for.
    private func backspaceKey(width: CGFloat) -> some View {
        let radius = cornerRadius(forKeyWidth: width)
        return Button(action: onBackspace) {
            Image(systemName: "delete.backward")
                .font(.system(size: glyphSize(forKeyWidth: width) * 0.85, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.ink : Theme.subtleInk)
                .frame(width: width, height: keyHeight)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(KeyPressStyle(cornerRadius: radius))
        .disabled(!isEnabled)
        .accessibilityLabel("Delete")
    }
}

/// What a key does while your thumb is on it.
///
/// A phone keyboard answers the moment it is touched rather than when it is let go, and a key that
/// looks identical mid-press reads as one that did not register — which on a board where a mistyped
/// letter costs a guess is worth more than decoration.
///
/// Deliberately not the system pop-up above the key: that exists because a thumb covers what it is
/// pressing on a full QWERTY, and it is also the thing people turn off. This is the quieter half —
/// the key itself dips and lights.
private struct KeyPressStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                // Over the label, so it tints a coloured key (one already marked green or grey by
                // a previous guess) as readily as a plain one.
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(0.2))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            // Down fast, back slowly. A press that eased *in* would feel like lag, which is the one
            // thing this is here to disprove.
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.04) : .spring(response: 0.3, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

#Preview {
    WordGuessKeyboardView(
        marks: WordGuessEvaluation.keyboardMarks(guesses: ["crane", "solid"], answer: "roast"),
        isEnabled: true,
        onLetter: { _ in },
        onBackspace: {}
    )
    .padding()
    .background(Theme.backgroundGradient)
}
