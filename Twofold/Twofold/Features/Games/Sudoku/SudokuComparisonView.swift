//
//  SudokuComparisonView.swift
//  Twofold
//
//  Both times, side by side, once both partners have solved the same grid.
//
//  It replaces the "solved — waiting for them" card on the play screen rather than being a screen
//  of its own. `gameDestinationView` sends every sudoku session to `SudokuGameView`, and the solved
//  board sitting directly above these numbers is the thing they are about — pushing a separate
//  screen would leave that board behind to say less.
//
//  The wording and the rounding live in `SudokuComparison`; this is only how they look.
//

import SwiftUI

struct SudokuComparisonView: View {
    let comparison: SudokuComparison

    var body: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)

                Text("You both solved it")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: Theme.Spacing.xs) {
                    timeRow(
                        name: "You",
                        elapsed: comparison.myElapsed,
                        aids: comparison.myAids,
                        isFaster: comparison.outcome == .me
                    )
                    Divider().opacity(0.5)
                    timeRow(
                        name: comparison.partnerName,
                        elapsed: comparison.partnerElapsed,
                        aids: comparison.partnerAids,
                        isFaster: comparison.outcome == .partner
                    )
                }
                .padding(.top, Theme.Spacing.xs)

                VStack(spacing: 2) {
                    Text(comparison.verdict)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                    // Said outright rather than left to be inferred from the two footnotes above.
                    // One of them solved it cold and the other asked: the times are comparable
                    // arithmetic and not comparable achievements, and a screen that shows a winner
                    // without saying so is rewarding whoever was most willing to ask for help.
                    if comparison.isLopsided {
                        Text("Only one of you did it unaided, so it's not quite a fair race.")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func timeRow(
        name: String,
        elapsed: TimeInterval,
        aids: SudokuSolveSummary?,
        isFaster: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        // Weight, not just colour, carries "this one was quicker" — the green below
                        // is a second signal rather than the only one, and the verdict says it in
                        // words.
                        .font(.subheadline.weight(isFaster ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Only when something was used. "No help" under both times on the ordinary
                    // solve would turn an honest footnote into an accusation.
                    if let used = aids?.aidsDescription {
                        Text(used)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text(SudokuComparison.clockText(elapsed))
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

    /// How long this solve took, against the longer of the two.
    ///
    /// The slower solve fills the track and the quicker one is short, which is the way round that
    /// matches what is being measured: less time is less bar. A dead heat draws two equal bars
    /// rather than two full ones, since the fraction is relative to the longest and the two are the
    /// same length.
    ///
    /// Floored at 4%, so a solve that was very much faster still draws something — a bar of no
    /// width reads as missing data rather than as a fast time.
    ///
    /// Decorative, and hidden from VoiceOver. The row above already reads the name, the time and
    /// any help used; a bar that announced itself would repeat all of that as a percentage.
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
    SudokuComparisonView(
        comparison: SudokuComparison(myElapsed: 134, partnerElapsed: 182, partnerName: "Erin")
    )
    .padding()
}

#Preview("Partner was faster") {
    SudokuComparisonView(
        comparison: SudokuComparison(myElapsed: 604, partnerElapsed: 417, partnerName: "Erin")
    )
    .padding()
}

#Preview("Dead heat") {
    SudokuComparisonView(
        comparison: SudokuComparison(myElapsed: 240, partnerElapsed: 240, partnerName: "Erin")
    )
    .padding()
}
