//
//  SudokuGameView.swift
//  Twofold
//
//  The play screen: clock, grid, keypad.
//
//  Leaving needs no confirmation: every tap is already written to `SudokuProgressCache`, so leaving
//  costs nothing. The back button itself comes from `puzzleScreenChrome`.
//

import SwiftUI

struct SudokuGameView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The puzzle on screen. `var`, not a fixed value built once from the initialiser, because
    /// "play another" swaps this screen's puzzle in place rather than pushing a second copy of the
    /// screen on top of the first — see `rematch()`.
    @State private var store: SudokuGameStore
    /// True when `start_sudoku_session` handed back a puzzle already in progress rather than a new
    /// one. The RPC has always reported this and nothing ever showed it, so tapping Hard silently
    /// returned a week-old grid with the clock already running.
    @State private var resumed: Bool
    /// The comparison being shared, while the share sheet is up.
    @State private var sharing: GameResultShareData?
    @State private var isStartingRematch = false
    @State private var rematchFailed: String?
    /// Toggled the moment both times exist. Drives the burst and the haptic together.
    ///
    /// Toggled rather than set true, because `ConfettiBurstView` animates on any *change* of its
    /// trigger. A flag that were set true and later cleared for the next puzzle would fire a second
    /// burst on the clearing, over a grid nobody has started yet.
    @State private var confettiTrigger = false
    /// Which puzzle the burst above has already been spent on — so it fires once per grid, and a
    /// rematch gets its own.
    @State private var celebratedSession: UUID?

    init(sessionID: UUID, resumed: Bool = false) {
        _store = State(initialValue: SudokuGameStore(sessionID: sessionID))
        _resumed = State(initialValue: resumed)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ErrorStateView(verbatim: message) { await store.load() }
            case .ready:
                board
            case .ended:
                GameAbandonedState(message: "This puzzle was ended, so it can't be finished.")
            }

            // Outside the switch, so it is mounted before the puzzle finishes loading. It animates
            // on a *change* of `trigger`, and a burst view that appeared already-true would never
            // see one.
            ConfettiBurstView(trigger: confettiTrigger)
        }
        .navigationTitle("Sudoku")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only once there are two times to show. A solve with nobody to compare against is
            // the "waiting for them" card, and a card of one time is not the thing this shares.
            if let shareData {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share", systemImage: "square.and.arrow.up") {
                        sharing = shareData
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .puzzleScreenChrome(
            store: store,
            abandon: PuzzleAbandonCopy(
                menuItem: "Abandon this puzzle",
                title: "Abandon this puzzle?",
                keepPlaying: "Keep playing",
                // `start_sudoku_session` resumes per couple, so one grid is shared between them.
                // Someone abandoning what they think is their own copy would otherwise wipe out a
                // partner's half-finished solve with no warning.
                message: "This ends it for both of you — \(appModel.partner.name)'s progress on this grid "
                    + "goes too. You'll be able to start a new "
                    + "\(store.difficulty?.displayName.lowercased() ?? "") puzzle straight away."
            ),
            reminderSentMessage: "\(appModel.partner.name) has been told their puzzle is waiting.",
            share: $sharing
        )
        // Both times exist, so the comparison is on screen. `initial: true` covers arriving at a
        // puzzle that was already finished on both sides — which is a first look at the result for
        // whoever solved first and walked away, and the burst is the point of opening it.
        //
        // It does mean revisiting an old puzzle bursts again. Deciding otherwise needs a stored
        // "you have seen this one", and missing the genuine reveal is the worse of the two misses.
        .onChange(of: store.partnerResult != nil, initial: true) { _, both in
            guard both, celebratedSession != store.sessionID else { return }
            celebratedSession = store.sessionID
            confettiTrigger.toggle()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
    }

    // MARK: - Playing another

    /// The way on from a finished puzzle, named for what it actually starts: another grid at the
    /// same difficulty.
    ///
    /// The other games put "Play Another Game" here and have it `dismiss()` back to the picker.
    /// Sudoku's picker is four difficulties rather than a library of decks, so going back to choose
    /// again from four options — having just played one of them — is a step that asks a question
    /// already answered.
    private var rematchButton: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: rematch) {
                HStack(spacing: Theme.Spacing.xs) {
                    if isStartingRematch {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(
                        store.difficulty.map { "Play another \($0.displayName.lowercased()) puzzle" }
                            ?? "Play another puzzle"
                    )
                    .font(.headline)
                }
            }
            .buttonStyle(.twofoldPrimary)
            .disabled(isStartingRematch)

            if let rematchFailed {
                Text(rematchFailed)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Swaps this screen's puzzle for a new one at the same difficulty.
    ///
    /// In place, rather than pushing a second `SudokuGameView` on top of this one: a rematch loop
    /// that pushes leaves a back stack of finished grids to walk out through, each one still holding
    /// a store. The two `.task(id: store.sessionID)` modifiers on the body are what make the swap
    /// safe — they stop the old clock and the old realtime stream when the id changes.
    ///
    /// `resumed` is taken from the RPC rather than assumed false. If the partner tapped this button
    /// first, `start_sudoku_session` hands back the grid they already started, which is the right
    /// answer — both of them end up on the same puzzle — and the RESUMED chip is then telling the
    /// truth about a clock that is not starting from zero.
    private func rematch() {
        guard let difficulty = store.difficulty, !isStartingRematch else { return }
        isStartingRematch = true
        rematchFailed = nil
        Task {
            defer { isStartingRematch = false }
            do {
                // Nothing is ended first, solo or paired: see `startAnother` for why the puzzle
                // just solved has to survive this.
                let started = try await store.startAnother(difficulty: difficulty)
                store.stopClock()
                store.link.stopRealtime()
                resumed = started.resumed
                store = SudokuGameStore(sessionID: started.sessionID)
            } catch {
                rematchFailed = "Couldn't start another puzzle. \(error.localizedDescription)"
            }
        }
    }

    /// Both solves, once both exist. Carries what each of them used as well as how long they took:
    /// see `SudokuComparison.isLopsided` for why the screen cannot show one without the other.
    private func comparison(for play: SudokuPlayState) -> SudokuComparison? {
        guard let partnerResult = store.partnerResult else { return nil }
        return SudokuComparison(
            myElapsed: play.elapsed,
            partnerElapsed: partnerResult.elapsed,
            partnerName: appModel.partner.name,
            myAids: SudokuSolveSummary(
                elapsed: play.elapsed, hintsUsed: play.hintsUsed, checksUsed: play.checksUsed
            ),
            partnerAids: partnerResult
        )
    }

    /// Non-nil exactly when there is a comparison on screen — both solved, so both times exist.
    ///
    /// The difficulty goes in `title` because that is the whole of what the card says about which
    /// puzzle this was: there is no deck name to use, and "Hard sudoku" tells a stranger seeing the
    /// image more than the grid's own identity ever could.
    private var shareData: GameResultShareData? {
        guard let play = store.play, play.isComplete,
              let partnerResult = store.partnerResult,
              let difficulty = store.difficulty
        else { return nil }

        return GameResultShareData(
            gameType: .sudoku,
            title: "\(difficulty.displayName) Sudoku",
            isDaily: false,
            me: appModel.currentUser,
            partner: appModel.partner,
            matchPercent: nil,
            triviaMyScore: nil,
            triviaPartnerScore: nil,
            triviaTotalRounds: nil,
            deepConversationRounds: nil,
            dailyStreak: nil,
            sudokuMyElapsed: play.elapsed,
            sudokuPartnerElapsed: partnerResult.elapsed,
            sudokuMyAids: SudokuSolveSummary(
                elapsed: play.elapsed, hintsUsed: play.hintsUsed, checksUsed: play.checksUsed
            ),
            sudokuPartnerAids: partnerResult
        )
    }

    @ViewBuilder
    private var board: some View {
        if let generated = store.generated, let play = store.play {
            VStack(spacing: Theme.Spacing.md) {
                statusBar(play: play)

                SudokuBoardView(
                    puzzle: generated.puzzle,
                    play: play,
                    conflicts: store.conflicts,
                    mistakes: store.mistakes,
                    selected: store.selected,
                    onSelect: { store.select($0) }
                )
                // `.md`, matching the status bar above and the comparison card below. It was `.sm`,
                // which left the grid and the keypad noticeably wider than everything else on the
                // screen and put the outer keys hard against the edges.
                .padding(.horizontal, Theme.Spacing.md)

                if play.isComplete {
                    if let comparison = comparison(for: play) {
                        VStack(spacing: Theme.Spacing.sm) {
                            SudokuComparisonView(comparison: comparison)
                            // Under the times, never above them. The race is the thing they came
                            // back for, and a button offering the next one is the first thing an
                            // eye lands on if it is put first.
                            rematchButton
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    } else {
                        solvedCard(play: play)
                    }
                } else {
                    controls
                    keypad
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - Status

    private func statusBar(play: SudokuPlayState) -> some View {
        HStack {
            if let difficulty = store.difficulty {
                Text(difficulty.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.surface, in: Capsule())
            }
            // Shown until it is solved, not just for a moment on arrival: the surprise this
            // answers is a clock that starts at 4:12, and that is just as confusing ten seconds in
            // as it is on the first frame.
            if resumed, !play.isComplete {
                Text("Resumed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.surface, in: Capsule())
                    .accessibilityLabel("Resumed from an earlier session")
            }
            Spacer()
            Label(PuzzleClock.text(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                // Without this the whole row twitches every second as the digits change width.
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Controls

    /// Same spacing and margins as the keypad below it, so the two rows line up rather than each
    /// finding its own edges.
    ///
    /// Was `.lg` with fixed 64pt buttons, which fitted three. Check and Hint made five: 320pt of
    /// buttons and 96pt of gaps is 416pt on a 393pt screen, so the row ran off both sides.
    private var controls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            controlButton("arrow.uturn.backward", label: "Undo", enabled: store.canUndo) {
                store.undo()
            }
            controlButton("eraser", label: "Erase", enabled: store.selected != nil) {
                store.erase()
            }
            controlButton(
                store.isNotesMode ? "pencil.circle.fill" : "pencil.circle",
                label: store.isNotesMode ? "Notes on" : "Notes",
                enabled: true,
                isActive: store.isNotesMode
            ) {
                store.isNotesMode.toggle()
            }
            controlButton("checkmark.circle", label: "Check", enabled: true) {
                store.checkMistakes()
            }
            controlButton("lightbulb", label: "Hint", enabled: true) {
                store.useHint()
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func controlButton(
        _ icon: String,
        label: String,
        enabled: Bool,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon).font(.title3)
                // Five words across one row cannot fit at accessibility sizes: they were cut to
                // "Un…", "Era…". There the row keeps its icons, the way a tab bar does, and a long
                // press shows the name in the large content viewer.
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary)
            // Flexible rather than fixed: five buttons share whatever the row has, so adding a
            // sixth later narrows them instead of overflowing. At least 52pt tall, and taller
            // when the icon has grown with the text size.
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.xsmall, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: icon) }
    }

    // MARK: - Keypad

    private var keypad: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(1...9, id: \.self) { digit in
                let value = UInt8(digit)
                let placed = store.remaining(of: value) <= 0
                Button {
                    store.enter(value)
                } label: {
                    Text(String(digit))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(placed ? Theme.textSecondary : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.xsmall, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                // Dimmed, not disabled. All nine of a digit being on the board usually means it is
                // finished — but if one of them is wrong, the player still needs to be able to type
                // it somewhere else while they work out which.
                .opacity(placed ? 0.45 : 1)
                .accessibilityLabel("\(digit)")
                .accessibilityHint(placed ? "All nine placed" : "\(store.remaining(of: value)) remaining")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Solved

    @ViewBuilder
    private func solvedCard(play: SudokuPlayState) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            solvedSummary(play: play)

            // Below the card rather than inside it: `GameReminderButton` is filled with
            // `Theme.surface` to read as raised against the page, which is the one colour
            // it would vanish into within a `SectionCard`. Same placement the deck games use.
            //
            // `partnerConnected`, not `hasCouple`, here and in `solvedSummary`. Despite its name
            // `hasCouple` means "signed in and past onboarding" — it is what `RootView` routes on —
            // so it is true for somebody playing alone too. Reading it as "paired" told every solo
            // player to wait for a partner called "Partner", offered to remind them, and hid "Play
            // another", which is the only way on from a solo solve.
            if appModel.session.partnerConnected {
                GameReminderButton(isSending: store.link.isSendingReminder, action: remindPartner)
            }
        }
        // On the stack rather than the card, so the button below it is inset to match.
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func solvedSummary(play: SudokuPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.success)
                Text("Solved in \(PuzzleClock.text(play.elapsed))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                // Nobody to wait for when there is nobody paired. `start_sudoku_session` gives an
                // unpaired player a session of their own with a null couple, so this card is what
                // they see every time they finish — and the version naming a partner was promising
                // a comparison that could never arrive, from a person who does not exist.
                // Only "saved" once the server has it. Before, this said so whether or not the one
                // send had landed, and the partner it promised a comparison to was never told.
                Text(
                    store.resultPending
                        ? "Your time is saved on this phone and will be sent as soon as it can be."
                        : appModel.session.partnerConnected
                        ? "Your time is saved. You'll see how it compares once \(appModel.partner.name) finishes theirs."
                        : "Your time is saved."
                )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    // Both of this card's sentences carry a name or a difficulty, so both are long
                    // enough to wrap — and a card that is being compressed truncates whichever one
                    // does not insist on its own height.
                    .fixedSize(horizontal: false, vertical: true)

                // The solo player's way on. Paired, there is a comparison coming and the reminder
                // button below the card is the thing to do about it; alone there is nothing to
                // wait for.
                //
                // The line that used to sit here — "Don't want to wait? Abandon it from the menu
                // above…" — pointed at a menu that isn't on screen once the puzzle is solved, so
                // it named a way out nobody could take from where they were standing.
                if !appModel.session.partnerConnected {
                    Divider().opacity(0.5)
                    rematchButton
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The same `gameReminder` push the other four games send from `GameCompletionView`, rather
    /// than a sudoku-specific one — it is the identical situation, and a second notification type
    /// saying the same thing is a second thing to keep in step with the copy.
    private func remindPartner() {
        // The difficulty is always set in practice, but it lands inside quotation marks in the
        // push — `wants you to complete "Hard Sudoku"` — so a nil would read as a leading space
        // inside them rather than as nothing.
        store.link.remindPartner(detail: store.difficulty.map { "\($0.displayName) Sudoku" } ?? "Sudoku")
    }
}
