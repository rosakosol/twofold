//
//  WordGuessEntryView.swift
//  Twofold
//
//  Word Guess's front door. Stands in for the deck list every other game type opens, in the same
//  way `SudokuDifficultyPickerView` does — there is no bank of content to list.
//
//  It exists rather than the hub card pushing straight into the board because starting one is a
//  round trip that can legitimately refuse: a Plus couple gets one word a day, and "come back
//  tomorrow, or upgrade" is an answer this screen has to be able to give.
//

import SwiftUI

struct WordGuessEntryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isStarting = false
    @State private var route: UUID?
    @State private var showingPaywall = false
    @State private var errorMessage: String?
    @State private var records: [GameRecord] = []
    @State private var limitReached = false
    @State private var history: [BackendService.WordGuessHistoryEntry] = []

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("The same word on both your phones. Six guesses each, then compare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                GameRecordCard(
                    records: records.filter { $0.gameType == .wordGuess },
                    partnerName: appModel.partner.name,
                    formatBest: { WordGuessComparison.guessText(Int($0)) }
                )

                howItWorks

                if limitReached {
                    limitCard
                } else {
                    startButton
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                allowanceNote

                previousGames
            }
            .padding(Theme.Spacing.md)
        }
        .background(ScreenBackground())
        .navigationTitle(GameType.wordGuess.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Reloaded every time the screen appears, not once: coming back here after playing is
        // exactly when the numbers have changed.
        .task {
            async let fetchedRecords = BackendService.fetchGameRecords()
            async let fetchedHistory = try? BackendService.fetchWordGuessHistory()
            records = await fetchedRecords
            history = await fetchedHistory ?? history
        }
        .navigationDestination(item: $route) { sessionID in
            WordGuessGameView(sessionID: sessionID)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    private var howItWorks: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                rule(.correct, "Right letter, right place.")
                rule(.present, "In the word, somewhere else.")
                rule(.absent, "Not in the word at all.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rule(_ mark: WordGuessMark, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 5)
                .fill(mark.tileColor)
                .frame(width: 30, height: 30)
                .overlay(
                    Text("A")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(mark.tileTextColor)
                )
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mark.accessibilityDescription). \(text)")
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: Theme.Spacing.xs) {
                if isStarting { ProgressView().controlSize(.small).tint(.white) }
                Text("Play today's word")
                    .font(.headline)
            }
        }
        .buttonStyle(.twofoldPrimary)
        .disabled(isStarting)
    }

    /// Shown instead of the button once the server has refused, rather than letting them tap into
    /// the same refusal again.
    private var limitCard: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.success)
                Text("That's today's word done")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("A new one arrives tomorrow. Premium has no daily limit.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See Premium") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Said before they hit it rather than only after, so the limit is a known rule of the game
    /// instead of a surprise on the second tap.
    @ViewBuilder
    private var allowanceNote: some View {
        if !isPremium && !limitReached {
            Text("One word a day on Plus. Premium has no daily limit.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Previous games

    /// Every recent word, newest first: when it was, what it was, and how each of you did.
    ///
    /// The word shows only once you've finished that board, so a game still in play is never spoiled
    /// by its own row, and your partner's score only once you both have (the database keeps their
    /// response from you until then).
    @ViewBuilder
    private var previousGames: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Previous games")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Theme.Spacing.sm)

                SectionCard {
                    VStack(spacing: 0) {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            Button { open(entry) } label: { historyRow(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: BackendService.WordGuessHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mine == nil ? "In progress" : (WordGuessWords.answer(for: entry.puzzleID)?.uppercased() ?? "—"))
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(Theme.textPrimary)
                Text(entry.playedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                scoreLine(name: "You", summary: entry.mine, pending: "Not finished")
                scoreLine(
                    name: appModel.partner.name,
                    summary: entry.partner,
                    pending: entry.mine == nil ? "" : "Waiting"
                )
            }
            if canOpen(entry) {
                Image(systemName: entry.mine != nil && entry.partner != nil && !isPremium ? "lock.fill" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func scoreLine(name: String, summary: WordGuessSummary?, pending: String) -> some View {
        if let summary {
            Text("\(name): \(Text(WordGuessComparison.scoreText(summary)))")
                .font(.caption)
                .foregroundStyle(summary.solved ? Theme.textPrimary : Theme.textSecondary)
        } else if !pending.isEmpty {
            Text("\(name): \(pending)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// An abandoned game has nothing to open; anything else opens on the board.
    private func canOpen(_ entry: BackendService.WordGuessHistoryEntry) -> Bool {
        entry.status != .abandoned
    }

    /// A finished game's results are a Premium feature: on Plus the row says how it went, and tapping
    /// it offers Premium. A game still being played opens on any plan, since that is only resuming
    /// it, the same as the Play button.
    private func open(_ entry: BackendService.WordGuessHistoryEntry) {
        guard canOpen(entry) else { return }
        let finished = entry.mine != nil && entry.partner != nil
        if finished && !isPremium {
            showingPaywall = true
        } else {
            route = entry.id
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                let session = try await BackendService.startWordGuessSession()
                route = session.sessionID
            } catch BackendError.wordGuessDailyLimit {
                // Not an error, and deliberately not shown as one: the allowance working is the
                // most ordinary thing that can happen here.
                limitReached = true
            } catch {
                errorMessage = "Couldn't start today's word. \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack { WordGuessEntryView() }
        .environment(AppModel())
}
