//
//  WordGuessComparisonView.swift
//  Twofold
//
//  Both results, side by side, once both partners have finished the same word.
//
//  Replaces the "finished — waiting for them" card on the play screen rather than being a screen of
//  its own, exactly as sudoku's does: the board they just played is directly above these numbers
//  and is the thing they are about.
//
//  The wording lives in `WordGuessComparison`; this is only how it looks.
//

import SwiftUI

struct WordGuessComparisonView: View {
    // Both faces, so a result screen says who at a glance rather than only in words.
    @Environment(AppModel.self) private var appModel

    let comparison: WordGuessComparison

    var body: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: headerIcon)
                    .font(.largeTitle)
                    .foregroundStyle(headerColor)

                Text(headerText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                VStack(spacing: Theme.Spacing.xs) {
                    resultRow(person: appModel.currentUser, name: "You", summary: comparison.mine, isLeader: comparison.outcome == .me)
                    Divider().opacity(0.5)
                    resultRow(
                        person: appModel.partner,
                        name: comparison.partnerName,
                        summary: comparison.theirs,
                        isLeader: comparison.outcome == .partner
                    )
                }
                .padding(.top, Theme.Spacing.xs)

                Text(comparison.verdict)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Neither of them getting it is a real outcome and should not be dressed up as a win. The seal
    /// is for a board somebody actually solved.
    private var headerIcon: String {
        comparison.mine.solved || comparison.theirs.solved ? "checkmark.seal.fill" : "clock.badge.xmark"
    }

    private var headerColor: Color {
        comparison.mine.solved || comparison.theirs.solved ? Theme.leafGreen : Theme.subtleInk
    }

    private var headerText: String {
        switch (comparison.mine.solved, comparison.theirs.solved) {
        case (true, true): "You both got it"
        case (false, false): "Nobody got this one"
        default: "One of you got it"
        }
    }

    private func resultRow(person: Person, name: String, summary: WordGuessSummary, isLeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                AvatarView(person: person, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        // Weight as well as colour, so "who did better" is not carried by hue
                        // alone — and the verdict underneath says it in words regardless.
                        .font(.subheadline.weight(isLeader ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Time is recorded but never decides the outcome, so it sits here as a
                    // footnote rather than alongside the score as if it were being compared.
                    Text(PuzzleClock.text(summary.elapsed))
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                        .monospacedDigit()
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text(WordGuessComparison.scoreText(summary))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        !summary.solved ? Theme.subtleInk : isLeader ? Theme.leafGreenText : Theme.ink
                    )
            }
            .accessibilityElement(children: .combine)

            guessPips(summary)
        }
    }

    /// One pip per guess spent, out of six.
    ///
    /// The same job sudoku's time bars do — the difference between 3/6 and 5/6 as something seen
    /// before it is read — but counted rather than measured, because the score is a small whole
    /// number and a proportional bar of it would be false precision.
    ///
    /// Decorative and hidden from VoiceOver: the row above already reads the score.
    private func guessPips(_ summary: WordGuessSummary) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<WordGuessWords.maxGuesses, id: \.self) { index in
                Capsule()
                    .fill(pipColor(index: index, summary: summary))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func pipColor(index: Int, summary: WordGuessSummary) -> Color {
        guard index < summary.guessCount else { return Theme.subtleInk.opacity(0.15) }
        // A miss fills all six and none of them green — the board was used up without getting
        // there, which is exactly what the row should look like.
        return summary.solved ? Theme.leafGreen : Theme.subtleInk.opacity(0.45)
    }
}

#Preview("You won") {
    WordGuessComparisonView(comparison: WordGuessComparison(
        mine: WordGuessSummary(guessCount: 3, solved: true, elapsed: 95),
        theirs: WordGuessSummary(guessCount: 5, solved: true, elapsed: 210),
        partnerName: "Erin"
    ))
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("Dead heat") {
    WordGuessComparisonView(comparison: WordGuessComparison(
        mine: WordGuessSummary(guessCount: 4, solved: true, elapsed: 130),
        theirs: WordGuessSummary(guessCount: 4, solved: true, elapsed: 160),
        partnerName: "Erin"
    ))
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("They missed it") {
    WordGuessComparisonView(comparison: WordGuessComparison(
        mine: WordGuessSummary(guessCount: 4, solved: true, elapsed: 130),
        theirs: WordGuessSummary(guessCount: 6, solved: false, elapsed: 300),
        partnerName: "Erin"
    ))
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("Nobody got it") {
    WordGuessComparisonView(comparison: WordGuessComparison(
        mine: WordGuessSummary(guessCount: 6, solved: false, elapsed: 240),
        theirs: WordGuessSummary(guessCount: 6, solved: false, elapsed: 280),
        partnerName: "Erin"
    ))
    .padding()
    .background(Theme.backgroundGradient)
}
