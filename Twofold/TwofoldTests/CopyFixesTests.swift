//
//  CopyFixesTests.swift
//  TwofoldTests
//
//  Words that were wrong for the person reading them: a plural (HOME-16), a phantom partner for
//  someone playing alone (GAME-9), and "Reminder sent" for a reminder that never left (GAME-11).
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct CopyFixesTests {

    // MARK: HOME-16

    @Test("one day to go is singular")
    func oneDayToGo() {
        let days = 1
        #expect(String(localized: "\(days) days to go") == "1 day to go")
    }

    @Test("several days to go stays plural")
    func severalDaysToGo() {
        let days = 12
        #expect(String(localized: "\(days) days to go") == "12 days to go")
    }

    // MARK: GAME-9

    @Test("abandoning a Sudoku alone doesn't mention a partner")
    func soloAbandon() {
        let copy = PuzzleAbandonCopy.sudoku(partnerName: nil, difficulty: .easy)
        #expect(!copy.message.contains("both of you"), "Told someone playing alone: \(copy.message)")
        #expect(!copy.message.contains("Partner"), "Told someone playing alone: \(copy.message)")
    }

    @Test("abandoning a shared Sudoku names the partner")
    func pairedAbandon() {
        let copy = PuzzleAbandonCopy.sudoku(partnerName: "Sam", difficulty: .hard)
        #expect(copy.message.contains("Sam's progress"))
        #expect(copy.message.contains("new hard puzzle"))
    }

    @Test("with no difficulty there is no double space")
    func abandonWithoutDifficulty() {
        let copy = PuzzleAbandonCopy.sudoku(partnerName: "Sam", difficulty: nil)
        #expect(!copy.message.contains("  "), "\(copy.message)")
    }

    @Test("a Premium player alone isn't told to wait for tomorrow")
    func premiumAloneWordGuess() {
        let line = WordGuessGameView.aloneFinishedLine(isPremium: true).resolved
        #expect(!line.contains("tomorrow"), "Premium has no daily limit, but was told: \(line)")
    }

    @Test("a Plus player alone is")
    func plusAloneWordGuess() {
        #expect(WordGuessGameView.aloneFinishedLine(isPremium: false).resolved == "A new word is waiting tomorrow.")
    }

    // MARK: GAME-11

    private func link(_ backend: FakePuzzleBackend) -> PuzzleResultLink {
        PuzzleResultLink(sessionID: UUID(), gameType: .sudoku, backend: backend, queue: MemoryGameResponseQueue())
    }

    @Test("a reminder that doesn't send says so")
    func failedReminder() async {
        let backend = FakePuzzleBackend(gameType: .sudoku)
        backend.isOffline = true
        let link = link(backend)
        await link.remindPartner(detail: "Easy Sudoku").value
        #expect(link.reminderResult == .failed, "Offline, the screen still said \"Reminder sent\"")
        #expect(!link.isSendingReminder)
    }

    @Test("a reminder that sends says it was sent")
    func sentReminder() async {
        let backend = FakePuzzleBackend(gameType: .sudoku)
        let link = link(backend)
        await link.remindPartner(detail: "Easy Sudoku").value
        #expect(link.reminderResult == .sent)
        #expect(backend.reminders == ["Easy Sudoku"])
    }
}
