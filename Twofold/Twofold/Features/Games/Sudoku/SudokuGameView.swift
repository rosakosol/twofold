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

    @Environment(\.scenePhase) private var scenePhase
    @State private var store: SudokuGameStore

    init(sessionID: UUID) {
        self.sessionID = sessionID
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
        .task {
            await store.load()
            store.startClock()
        }
        .onDisappear { store.stopClock() }
        .onChange(of: scenePhase) { _, phase in
            // The clock measures time at the board, so backgrounding stops it. Without this a
            // puzzle left open in a pocket would report an afternoon's solve.
            if phase == .active { store.startClock() } else { store.stopClock() }
        }
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
                    selected: store.selected,
                    onSelect: { store.select($0) }
                )
                .padding(.horizontal, Theme.Spacing.sm)

                if play.isComplete {
                    solvedCard(play: play)
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
            Spacer()
            Label(Self.clockText(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
                // Without this the whole row twitches every second as the digits change width.
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    static func clockText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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
        .padding(.horizontal, Theme.Spacing.sm)
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
