//
//  SudokuGameView.swift
//  Twofold
//
//  The play screen: clock, grid, keypad.
//
//  It keeps the system back button rather than the custom `GameBackButton` the other games use.
//  Those hide it so leaving mid-round can ask for confirmation, because their progress is only in
//  memory. Here every tap is already written to `SudokuProgressCache`, so leaving costs nothing and
//  there is nothing to confirm — and the system button comes with the large tap target UIKit gives
//  it, which a custom one does not.
//

import SwiftUI

struct SudokuGameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    /// The puzzle on screen. `var`, not a fixed value built once from the initialiser, because
    /// "play another" swaps this screen's puzzle in place rather than pushing a second copy of the
    /// screen on top of the first — see `rematch()`.
    @State private var store: SudokuGameStore
    /// True when `start_sudoku_session` handed back a puzzle already in progress rather than a new
    /// one. The RPC has always reported this and nothing ever showed it, so tapping Hard silently
    /// returned a week-old grid with the clock already running.
    @State private var resumed: Bool
    @State private var showingShare = false
    @State private var confirmingAbandon = false
    @State private var isSendingReminder = false
    @State private var showingReminderSent = false
    @State private var abandonFailed: String?
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
            Theme.backgroundGradient
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                GameErrorState(message: message)
                    .padding(Theme.Spacing.lg)
            case .ready:
                board
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
                        showingShare = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
            // Only while the puzzle is unsolved. Once it is finished the thing you want is the
            // comparison, and abandoning would throw away a solve that is already submitted.
            if store.play?.isComplete == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmingAbandon = true
                        } label: {
                            Label("Abandon this puzzle", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Abandon this puzzle?",
            isPresented: $confirmingAbandon,
            titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) { abandon() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            // Named plainly because the session is the couple's, not this player's:
            // `start_sudoku_session` resumes per couple, so one grid is shared between them and
            // ending it ends it for both. Someone abandoning what they think is their own copy
            // would otherwise wipe out a partner's half-finished solve with no warning.
            Text(
                "This ends it for both of you — \(appModel.partner.name)'s progress on this grid "
                + "goes too. You'll be able to start a new "
                + "\(store.difficulty?.displayName.lowercased() ?? "") puzzle straight away."
            )
        }
        .alert("Couldn't abandon", isPresented: .constant(abandonFailed != nil)) {
            Button("OK") { abandonFailed = nil }
        } message: {
            Text(abandonFailed ?? "")
        }
        .sheet(isPresented: $showingShare) {
            if let shareData {
                GameResultsShareView(data: shareData)
            }
        }
        // Keyed on the session rather than on the view's lifetime: "play another" replaces `store`
        // in place, and a plain `.task` would leave both of these running against the puzzle that
        // is no longer on screen — the old clock still ticking, the old realtime stream still
        // listening. `.task(id:)` cancels and restarts them on the swap.
        .task(id: store.sessionID) {
            await store.load()
            store.startClock()
        }
        // Its own task: `subscribeRealtime()` loops until cancelled, so folding it into the one
        // above would mean the board waited on a stream that never ends.
        .task(id: store.sessionID) { await store.subscribeRealtime() }
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
        .onDisappear {
            store.stopClock()
            store.stopRealtime()
        }
        .onChange(of: scenePhase) { _, phase in
            // The clock measures time at the board, so backgrounding stops it. Without this a
            // puzzle left open in a pocket would report an afternoon's solve.
            if phase == .active { store.startClock() } else { store.stopClock() }
        }
    }

    /// Ends the shared session and goes back to the picker, where starting the same difficulty now
    /// gets a genuinely new grid instead of this one again.
    ///
    /// Back rather than straight into a replacement: the picker owns navigation, and a puzzle that
    /// silently swapped itself for a different one under the same screen would be the same
    /// surprise this is here to fix.
    private func abandon() {
        let id = store.sessionID
        store.stopClock()
        Task {
            do {
                try await BackendService.abandonGameSession(id: id)
                // The device's own copy goes too, or the grid would sit in the cache forever —
                // harmless, but it is the abandoned puzzle's last trace and nothing will ever ask
                // for it again.
                if let me = BackendService.currentUserID {
                    SudokuProgressCache.remove(sessionID: id, responderID: me)
                }
                dismiss()
            } catch {
                abandonFailed = error.localizedDescription
            }
        }
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
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(isStartingRematch)

            if let rematchFailed {
                Text(rematchFailed)
                    .font(.caption)
                    .foregroundStyle(Theme.heartRedText)
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
                // A solo session never reaches `completed`: `advance_game_session` waits for a
                // second responder who is never coming, so it sits in `waiting_for_partner` and
                // `start_sudoku_session` would hand back this same solved grid. Ending it first is
                // what makes the next one new. Paired, the session is already `completed` by the
                // time this button exists — both times are on screen — so there is nothing to end.
                if !appModel.hasCouple {
                    try await BackendService.abandonGameSession(id: store.sessionID)
                    if let me = BackendService.currentUserID {
                        SudokuProgressCache.remove(sessionID: store.sessionID, responderID: me)
                    }
                }
                let started = try await BackendService.startSudokuSession(difficulty: difficulty)
                store.stopClock()
                store.stopRealtime()
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
    /// puzzle this was: there is no deck name to use, and "HARD SUDOKU" tells a stranger seeing the
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
                Text(difficulty.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.skyBlueText)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.cardBackground, in: Capsule())
            }
            // Shown until it is solved, not just for a moment on arrival: the surprise this
            // answers is a clock that starts at 4:12, and that is just as confusing ten seconds in
            // as it is on the first frame.
            if resumed, !play.isComplete {
                Text("RESUMED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.subtleInk)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.cardBackground, in: Capsule())
                    .accessibilityLabel("Resumed from an earlier session")
            }
            Spacer()
            Label(PuzzleClock.text(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
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
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
            .foregroundStyle(isActive ? Theme.skyBlueText : Theme.ink)
            // Flexible rather than fixed: five buttons share whatever the row has, so adding a
            // sixth later narrows them instead of overflowing.
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
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
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(placed ? Theme.subtleInk : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Theme.cardBackground,
                            in: RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous)
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
            // `Theme.cardBackground` to read as raised against the page, which is the one colour
            // it would vanish into within a `SectionCard`. Same placement the deck games use.
            if appModel.hasCouple {
                GameReminderButton(isSending: isSendingReminder, action: remindPartner)
            }
        }
        // On the stack rather than the card, so the button below it is inset to match.
        .padding(.horizontal, Theme.Spacing.md)
        .alert("Nudge sent", isPresented: $showingReminderSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(appModel.partner.name) has been told their puzzle is waiting.")
        }
    }

    private func solvedSummary(play: SudokuPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)
                Text("Solved in \(PuzzleClock.text(play.elapsed))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                // Nobody to wait for when there is nobody paired. `start_sudoku_session` gives an
                // unpaired player a session of their own with a null couple, so this card is what
                // they see every time they finish — and the version naming a partner was promising
                // a comparison that could never arrive, from a person who does not exist.
                Text(
                    appModel.hasCouple
                        ? "Your time is saved. You'll see how it compares once \(appModel.partner.name) finishes theirs."
                        : "Your time is saved."
                )
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
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
                if !appModel.hasCouple {
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
        isSendingReminder = true
        Task {
            await BackendService.notifyPartner(
                event: .gameReminder,
                // The difficulty is always set in practice, but it lands inside quotation marks
                // in the push — `wants you to complete "Hard Sudoku"` — so a nil would read as a
                // leading space inside them rather than as nothing.
                detail: store.difficulty.map { "\($0.displayName) Sudoku" } ?? "Sudoku",
                sessionID: store.sessionID,
                gameType: .sudoku
            )
            isSendingReminder = false
            showingReminderSent = true
        }
    }
}
