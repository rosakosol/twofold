//
//  WordSearchComparisonView.swift
//  Twofold
//
//  Both times, side by side, once both partners have cleared the same grid.
//
//  Replaces the "cleared it — waiting for them" card on the play screen rather than being a screen
//  of its own, as sudoku's and Word Guess's do. The wording lives in `WordSearchComparison`.
//

import SwiftUI

struct WordSearchComparisonView: View {
    let comparison: WordSearchComparison

    var body: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)

                Text("You both cleared it")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: Theme.Spacing.xs) {
                    timeRow(
                        name: "You",
                        elapsed: comparison.myElapsed,
                        isFaster: comparison.outcome == .me
                    )
                    Divider().opacity(0.5)
                    timeRow(
                        name: comparison.partnerName,
                        elapsed: comparison.partnerElapsed,
                        isFaster: comparison.outcome == .partner
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

    private func timeRow(name: String, elapsed: TimeInterval, isFaster: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(name)
                    // Weight as well as colour, so the quicker of the two is not carried by hue
                    // alone — and the verdict underneath says it in words regardless.
                    .font(.subheadline.weight(isFaster ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.sm)
                Text(PuzzleClock.text(elapsed))
                    .font(.title3.weight(.semibold))
                    // Without this the two times sit on different grids and read as harder to
                    // compare than they are.
                    .monospacedDigit()
                    .foregroundStyle(isFaster ? Theme.leafGreenText : Theme.ink)
            }
            .accessibilityElement(children: .combine)

            timeBar(elapsed, isFaster: isFaster)
        }
    }

    /// How long this clear took, against the longer of the two — the same bar sudoku's comparison
    /// draws, and for the same reason: the margin is something to see before it is read.
    ///
    /// The slower time fills the track and the quicker one is short, because less time is less bar.
    /// Floored at 4% so a much faster clear still draws something; a bar of no width reads as
    /// missing data rather than as a fast time.
    ///
    /// Decorative and hidden from VoiceOver — the row above already reads the name and the time.
    private func timeBar(_ elapsed: TimeInterval, isFaster: Bool) -> some View {
        let longest = max(comparison.myElapsed, comparison.partnerElapsed, 1)
        let fraction = max(0.04, min(1, elapsed / longest))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtleInk.opacity(0.15))
                Capsule()
                    .fill(isFaster ? Theme.leafGreen : Theme.skyBlue)
                    .frame(width: max(4, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

#Preview("You were faster") {
    WordSearchComparisonView(comparison: WordSearchComparison(
        myElapsed: 154, partnerElapsed: 233, partnerName: "Erin", theme: .travel
    ))
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("Dead heat") {
    WordSearchComparisonView(comparison: WordSearchComparison(
        myElapsed: 200, partnerElapsed: 200, partnerName: "Erin", theme: .love
    ))
    .padding()
    .background(Theme.backgroundGradient)
}
