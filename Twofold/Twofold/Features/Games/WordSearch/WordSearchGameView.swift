//
//  WordSearchGameView.swift
//  Twofold
//
//  The play screen: the grid, the words still to find, and the clock.
//
//  Keeps the system back button for the reason sudoku does — every find is already written to
//  `PuzzleProgressCache`, so leaving costs nothing and there is nothing to confirm.
//

import PostHog
import SwiftUI

struct WordSearchGameView: View {
    @Environment(AppModel.self) private var appModel
    @State private var store: WordSearchGameStore
    /// Toggled when both results exist. Toggled rather than set, because `ConfettiBurstView`
    /// animates on any *change* of its trigger.
    @State private var confettiTrigger = false
    @State private var celebratedSession: UUID?

    init(sessionID: UUID) {
        _store = State(initialValue: WordSearchGameStore(sessionID: sessionID))
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                GameErrorState(message: message)
                    .padding(Theme.Spacing.lg)
            case .ready:
                content
            case .ended:
                GameAbandonedState(message: "This grid was ended, so it can't be finished.")
            }

            // Outside the switch so it is mounted before the grid loads — it animates on a change
            // of its trigger, and a burst view that appeared already-true would never see one.
            ConfettiBurstView(trigger: confettiTrigger)
        }
        .navigationTitle(GameType.wordSearch.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .puzzleScreenChrome(
            store: store,
            abandon: PuzzleAbandonCopy(
                menuItem: "Abandon this grid",
                title: "Abandon this grid?",
                keepPlaying: "Keep looking",
                // `start_word_search_session` resumes per couple and theme, so one grid is shared
                // between them and ending it ends it for both.
                message: appModel.partnerConnected
                    ? "This ends it for both of you — \(appModel.partner.name)'s progress on this grid goes too. You'll be able to start a new one straight away."
                    : "You'll be able to start a new grid straight away."
            ),
            reminderSentMessage: "\(appModel.partner.name) has been told their grid is waiting.",
            share: .constant(nil)
        )
        // Both results exist, so the comparison is on screen. `initial: true` covers arriving at a
        // grid already cleared on both sides — a first look at the result for whoever finished
        // first and walked away.
        .onChange(of: store.partnerResult != nil, initial: true) { _, both in
            guard both, celebratedSession != store.sessionID else { return }
            celebratedSession = store.sessionID
            confettiTrigger.toggle()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        // A small tap on every word found, not just at the end. Finding one is the thing this game
        // does, and eight of them with no feedback until the last is seven moments thrown away.
        .sensoryFeedback(.impact(weight: .light), trigger: store.play?.found.count ?? 0)
        .postHogScreenView("Games: Word Search")
    }

    @ViewBuilder
    private var content: some View {
        if let play = store.play {
            VStack(spacing: Theme.Spacing.sm) {
                statusBar(play: play)

                WordSearchGridView(
                    play: play,
                    selection: store.selection,
                    onBegin: { store.beginSelection(at: $0) },
                    onExtend: { store.extendSelection(to: $0) },
                    onEnd: { store.endSelection() }
                )
                .padding(.horizontal, Theme.Spacing.md)

                if play.isComplete {
                    finishedSection(play: play)
                        .padding(.horizontal, Theme.Spacing.md)
                } else {
                    wordList(play: play)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private func statusBar(play: WordSearchPlayState) -> some View {
        HStack {
            if let theme = store.theme {
                Text(theme.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.surface, in: Capsule())
            }
            Spacer()
            Text("\(play.found.count)/\(play.totalCount)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Label(PuzzleClock.text(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                // Without this the whole row twitches every second as the digits change width.
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    /// The words still to find, and the ones already found struck through.
    ///
    /// Found words stay on the list rather than disappearing from it. A list that shrinks as you
    /// play loses the record of what you did, and on a shared grid it is also the only place the
    /// two of you can compare notes on which ones were hard.
    private func wordList(play: WordSearchPlayState) -> some View {
        SectionCard {
            // A flowing wrap rather than a fixed grid: the words are between four and ten letters,
            // and a column wide enough for the longest leaves the shortest swimming.
            FlowLayout(spacing: Theme.Spacing.xs) {
                ForEach(play.puzzle.words, id: \.self) { word in
                    let isFound = play.isFound(word)
                    Text(word)
                        .font(.caption.weight(isFound ? .regular : .semibold))
                        .strikethrough(isFound)
                        .foregroundStyle(isFound ? Theme.textSecondary : Theme.textPrimary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            isFound ? Theme.success.opacity(0.15) : Theme.surface,
                            in: Capsule()
                        )
                        .accessibilityLabel(isFound ? "\(word), found" : word)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func finishedSection(play: WordSearchPlayState) -> some View {
        if let theirs = store.partnerResult, let theme = store.theme {
            WordSearchComparisonView(comparison: WordSearchComparison(
                myElapsed: play.elapsed,
                partnerElapsed: theirs.elapsed,
                partnerName: appModel.partner.name,
                theme: theme
            ))
        } else {
            clearedCard(play: play)
        }
    }

    private func clearedCard(play: WordSearchPlayState) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            clearedSummary(play: play)

            // Outside the card: `GameReminderButton` is filled with `Theme.surface` so it
            // reads as raised against the page, which is the one colour it would disappear into
            // inside a `SectionCard`. Same placement the deck games use.
            if appModel.partnerConnected {
                GameReminderButton(isSending: store.link.isSendingReminder) {
                    store.link.remindPartner(
                        detail: store.theme.map { "\($0.displayName) Word Search" } ?? GameType.wordSearch.displayName
                    )
                }
            }
        }
    }

    private func clearedSummary(play: WordSearchPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.success)

                Text("Cleared in \(PuzzleClock.text(play.elapsed))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                if store.resultPending {
                    Text("Your time is saved on this phone and will be sent as soon as it can be.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if appModel.partnerConnected {
                    Text("Your time is saved. You'll see how it compares once \(appModel.partner.name) has cleared theirs.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your time is saved.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
