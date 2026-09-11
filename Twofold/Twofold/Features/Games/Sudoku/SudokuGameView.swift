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
    let sessionID: UUID
    /// True when `start_sudoku_session` handed back a puzzle already in progress rather than a new
    /// one. The RPC has always reported this and nothing ever showed it, so tapping Hard silently
    /// returned a week-old grid with the clock already running.
    let resumed: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store: SudokuGameStore
    @State private var showingShare = false
    @State private var confirmingAbandon = false
    @State private var abandonFailed: String?

    init(sessionID: UUID, resumed: Bool = false) {
        self.sessionID = sessionID
        self.resumed = resumed
        _store = State(initialValue: SudokuGameStore(sessionID: sessionID))
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
        .task {
            await store.load()
            store.startClock()
        }
        // Its own task: `subscribeRealtime()` loops until cancelled, so folding it into the one
        // above would mean the board waited on a stream that never ends.
        .task { await store.subscribeRealtime() }
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
        let id = sessionID
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
                        SudokuComparisonView(comparison: comparison)
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
            Label(Self.clockText(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
                // Without this the whole row twitches every second as the digits change width.
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    /// The running clock and the comparison's finished times have to agree to the second — a solve
    /// that ended at 2:14 on this screen cannot become 2:13 alongside a partner's. One
    /// implementation, in `SudokuComparison`, is what makes that true by construction rather than
    /// by two copies happening to round the same way.
    static func clockText(_ elapsed: TimeInterval) -> String {
        SudokuComparison.clockText(elapsed)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Theme.Spacing.lg) {
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
            .frame(width: 64, height: 52)
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

    private func solvedCard(play: SudokuPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)
                Text("Solved in \(Self.clockText(play.elapsed))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("Your time is saved. You'll be able to see how it compares once your partner finishes theirs.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}
