//
//  GameRecordCard.swift
//  Twofold
//
//  The running record for one game, at the top of its entry screen.
//
//  One card shared by four games rather than four cards, because the thing being shown is the same
//  in all of them: how many each of you has won, and each of your bests. Sudoku is the exception
//  and stays as it is — it aggregates on the device from solves it has already fetched, and its
//  table is per-difficulty rather than a single line. Two implementations of one record is one too
//  many, but so is rewriting a working one to prove a point.
//

import SwiftUI

/// One row of `get_game_stats`.
///
/// `myBest` is deliberately unitless: guesses for Word Guess, seconds for Word Search, absent for
/// the board games. The screen asking always knows which game it asked about, and a column per unit
/// would be three columns null in every row but one.
struct GameRecord: Decodable, Identifiable, Equatable {
    let gameType: GameType
    /// The theme or difficulty, where the game keeps its record per variant.
    let variant: String?
    let myFinished: Int
    let partnerFinished: Int
    let myWins: Int
    let partnerWins: Int
    let draws: Int
    let myBest: Double?
    let partnerBest: Double?

    var id: String { "\(gameType.rawValue)-\(variant ?? "")" }

    /// Nothing has been finished on either side. Worth naming, because a card of zeroes is worse
    /// than no card: it says the feature exists and that you are bad at it.
    var isEmpty: Bool { myFinished == 0 && partnerFinished == 0 && decided == 0 }

    var decided: Int { myWins + partnerWins + draws }

    enum CodingKeys: String, CodingKey {
        case variant
        case gameType = "game_type"
        case myFinished = "my_finished"
        case partnerFinished = "partner_finished"
        case myWins = "my_wins"
        case partnerWins = "partner_wins"
        case draws = "draws"
        case myBest = "my_best"
        case partnerBest = "partner_best"
    }
}

struct GameRecordCard: View {
    let records: [GameRecord]
    let partnerName: String
    /// How to write a "best" for this game. Nil where the game has no best worth showing — the two
    /// board games, where the only record is the head-to-head.
    let formatBest: ((Double) -> String)?

    private var totals: (mine: Int, theirs: Int, drawn: Int) {
        records.reduce(into: (0, 0, 0)) { sum, record in
            sum.0 += record.myWins
            sum.1 += record.partnerWins
            sum.2 += record.draws
        }
    }

    var body: some View {
        if !records.allSatisfy(\.isEmpty) {
            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    headToHead

                    let withBests = records.filter { $0.myBest != nil || $0.partnerBest != nil }
                    if formatBest != nil, !withBests.isEmpty {
                        Divider().opacity(0.5)
                        // Named, rather than left to be inferred from the order. Two numbers
                        // separated by a slash say nothing about which is whose, and the one time
                        // somebody reads it backwards is the time they think they are losing.
                        HStack {
                            Text("Best")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.subtleInk)
                            Spacer(minLength: Theme.Spacing.sm)
                            Text("You")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                            Text("/")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk.opacity(0.6))
                            Text(partnerName)
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                                .lineLimit(1)
                        }
                        .accessibilityHidden(true)

                        ForEach(withBests) { record in
                            bestRow(record)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headToHead: some View {
        let score = totals
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Between you")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                tally(score.mine, name: "You", isAhead: score.mine > score.theirs)
                Text("–")
                    .font(.title3)
                    .foregroundStyle(Theme.subtleInk)
                tally(score.theirs, name: partnerName, isAhead: score.theirs > score.mine)

                if score.drawn > 0 {
                    Spacer(minLength: Theme.Spacing.sm)
                    // Draws sit beside the score rather than in it. A record of "3–3" that is
                    // really three wins each plus four draws is a different game from one with
                    // none, and folding them in would hide that.
                    Text(score.drawn == 1 ? "1 draw" : "\(score.drawn) draws")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
            }

            if score.mine + score.theirs + score.drawn == 0 {
                // Both have played, neither has beaten the other — which happens when only one of
                // them has finished anything yet.
                Text("Nothing decided yet.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Between you: you \(score.mine), \(partnerName) \(score.theirs), \(score.drawn) drawn")
    }

    private func tally(_ count: Int, name: String, isAhead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isAhead ? Theme.leafGreenText : Theme.ink)
            Text(name)
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
        }
    }

    private func bestRow(_ record: GameRecord) -> some View {
        HStack {
            Text(record.variant?.capitalized ?? "Best")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Spacing.sm)
            Text(bestText(record.myBest))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text("/")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
            Text(bestText(record.partnerBest))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.subtleInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.variant?.capitalized ?? "Best"): yours \(bestText(record.myBest)), theirs \(bestText(record.partnerBest))")
    }

    /// An em dash rather than a zero for a game neither has finished — zero is a score, and this is
    /// the absence of one.
    private func bestText(_ value: Double?) -> String {
        guard let value, let formatBest else { return "—" }
        return formatBest(value)
    }
}

#Preview("Word Guess") {
    GameRecordCard(
        records: [GameRecord(
            gameType: .wordGuess, variant: nil,
            myFinished: 12, partnerFinished: 11,
            myWins: 5, partnerWins: 4, draws: 2,
            myBest: 2, partnerBest: 3
        )],
        partnerName: "Erin",
        formatBest: { WordGuessComparison.guessText(Int($0)) }
    )
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("Chess — no bests") {
    GameRecordCard(
        records: [GameRecord(
            gameType: .chess, variant: nil,
            myFinished: 4, partnerFinished: 4,
            myWins: 1, partnerWins: 2, draws: 1,
            myBest: nil, partnerBest: nil
        )],
        partnerName: "Erin",
        formatBest: nil
    )
    .padding()
    .background(Theme.backgroundGradient)
}
