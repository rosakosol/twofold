//
//  GameResultShareData+Cards.swift
//  Twofold
//
//  What the share sheet shows and copies for each game (SHARE_REDESIGN.md §3.5 and §7.4): one
//  card per Deep Conversation question, one card for everything else, and the same content as
//  plain text ending "via twofold".
//

import Foundation

extension GameResultShareData {
    var shareKind: GameShareKind { GameShareKind(gameType) }

    /// Every card the sheet pages through. Empty only when there is nothing to show yet.
    var shareCards: [GameShareContent] {
        if let cells = connectFourCells, let status = connectFourStatus {
            return [.connectFour(
                status: status,
                cells: cells,
                winning: Set(connectFourWinning),
                firstName: connectFourFirstIsMe ? me.name : partner.name,
                secondName: connectFourFirstIsMe ? partner.name : me.name
            )]
        }
        if let mine = wordGuessMine, let theirs = wordGuessTheirs {
            return [.puzzle(subtitle: puzzleSubtitle, players: [
                puzzlePlayer(me.name, mine),
                puzzlePlayer(partner.name, theirs),
            ])]
        }
        if let mine = sudokuMyElapsed, let theirs = sudokuPartnerElapsed {
            let comparison = sudokuComparison(mine, theirs)
            return [.score(
                deck: title,
                columns: [
                    .init(value: PuzzleClock.text(mine), name: me.name, note: sudokuMyAids?.aidsDescription),
                    .init(value: PuzzleClock.text(theirs), name: partner.name, note: sudokuPartnerAids?.aidsDescription),
                ],
                caption: String(localized: comparison.sharedVerdict(myName: me.name))
            )]
        }
        if let mine = triviaMyScore, let theirs = triviaPartnerScore, let total = triviaTotalRounds {
            return [.score(
                deck: title,
                columns: [.init(value: "\(mine)", name: me.name), .init(value: "\(theirs)", name: partner.name)],
                caption: String(localized: "correct out of \(total)")
            )]
        }
        if let matchPercent {
            return [.similarity(deck: title, percent: matchPercent)]
        }
        return questionRounds.map { round in
            .questionAndAnswers(deck: title, question: round.question, answers: [
                .init(name: me.name, text: Self.answer(round.myAnswer)),
                .init(name: partner.name, text: Self.answer(round.partnerAnswer)),
            ])
        }
    }

    /// True when a card carries the partner's own words, which they agreed to reveal to you and
    /// not to everyone you might send this to. The sheet asks before it leaves the phone.
    var includesPartnerWords: Bool {
        shareCards.contains { if case .questionAndAnswers = $0 { true } else { false } }
    }

    /// "Copy as text": the card at `index` in full, including any answer the card had to cut short.
    func shareText(for index: Int) -> String {
        let cards = shareCards
        guard cards.indices.contains(index) else { return "" }
        var lines = ["\(shareKind.name) · \(title)", ""]

        switch cards[index] {
        case let .questionAndAnswers(_, question, answers):
            lines.append(question)
            lines.append("")
            lines += answers.map { "\($0.name): \($0.text)" }
        case let .similarity(_, percent):
            lines.append(String(localized: "\(me.name) & \(partner.name): \(percent)% answer similarity"))
        case let .score(_, columns, caption):
            lines += columns.map { column in
                [column.name, column.value, column.note.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            }
            lines.append(caption)
        case let .connectFour(status, cells, _, firstName, secondName):
            lines = ["Connect 4", "", status]
            for row in 0..<ConnectFourBoard.rows {
                lines.append((0..<ConnectFourBoard.columns).map { column -> String in
                    switch cells[row * ConnectFourBoard.columns + column] {
                    case .first: "🔴"
                    case .second: "🔵"
                    case nil: "⚪️"
                    }
                }.joined())
            }
            lines.append("🔵 \(secondName) · 🔴 \(firstName)")
        case .drawings:
            break
        case let .puzzle(subtitle, players):
            lines = ["\(shareKind.name) · \(subtitle)", ""]
            for player in players {
                lines.append("\(player.name) \(player.result)")
                // The usual spoiler-free squares: only the rows they played.
                lines += player.rows.filter { !$0.contains(.unused) }.map { row in
                    row.map { tile in
                        switch tile {
                        case .correct: "🟩"
                        case .present: "🟨"
                        case .absent, .unused: "⬛"
                        }
                    }.joined()
                }
                lines.append("")
            }
            lines.removeLast()
        }

        lines += ["", "via twofold"]
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private var questionRounds: [GameResultShareRound] {
        if let rounds = deepConversationRounds, !rounds.isEmpty { return rounds }
        guard let singleRoundQuestion else { return [] }
        return [GameResultShareRound(question: singleRoundQuestion, myAnswer: myAnswer ?? "", partnerAnswer: partnerAnswer ?? "")]
    }

    private static func answer(_ text: String) -> String {
        text.isEmpty ? String(localized: "Skipped this one") : text
    }

    private func sudokuComparison(_ mine: TimeInterval, _ theirs: TimeInterval) -> SudokuComparison {
        SudokuComparison(
            myElapsed: mine,
            partnerElapsed: theirs,
            partnerName: partner.name,
            myAids: sudokuMyAids,
            partnerAids: sudokuPartnerAids
        )
    }

    private var puzzleSubtitle: String {
        let date = (playedAt ?? .now).formatted(.dateTime.day().month(.wide))
        return String(localized: "Daily puzzle · \(date)")
    }

    private func puzzlePlayer(_ name: String, _ play: WordGuessPlayState) -> GameShareContent.PuzzlePlayer {
        let summary = WordGuessSummary(guessCount: play.guesses.count, solved: play.isSolved, elapsed: play.elapsed)
        var rows: [[GameShareTile]] = play.guesses.prefix(WordGuessWords.maxGuesses).map { guess in
            WordGuessEvaluation.marks(guess: guess, answer: play.answer).map { mark in
                switch mark {
                case .correct: .correct
                case .present: .present
                case .absent: .absent
                }
            }
        }
        let width = play.answer.count
        while rows.count < WordGuessWords.maxGuesses {
            rows.append(Array(repeating: .unused, count: width))
        }
        return .init(
            name: name,
            result: String(localized: WordGuessComparison.scoreText(summary)),
            solved: play.isSolved,
            rows: rows
        )
    }
}
