//
//  SudokuDifficultyPickerView.swift
//  Twofold
//
//  Sudoku's entry point. Every other game type opens `GameTypeDecksView` — a list of decks — and
//  sudoku has none, so this stands in its place: four difficulties instead of a content library.
//
//  Hard and Expert are Premium. The check here is only so the screen can show a lock and open the
//  paywall instead of starting a call that would be refused; `start_sudoku_session` enforces it for
//  real, and is the only enforcement that counts.
//

import SwiftUI

struct SudokuDifficultyPickerView: View {
    @Environment(AppModel.self) private var appModel

    @State private var starting: SudokuDifficulty?
    @State private var route: UUID?
    @State private var showingPaywall = false
    @State private var errorMessage: String?

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("The same grid on both your phones. Solve it apart, compare when you're done.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)

                ForEach(SudokuDifficulty.allCases, id: \.self) { difficulty in
                    row(difficulty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRedText)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Sudoku")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { sessionID in
            SudokuGameView(sessionID: sessionID)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    private func row(_ difficulty: SudokuDifficulty) -> some View {
        let locked = difficulty.requiresPremium && !isPremium
        return Button {
            errorMessage = nil
            if locked {
                showingPaywall = true
            } else {
                start(difficulty)
            }
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(difficulty.displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(difficulty.blurb)
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer()
                    if starting == difficulty {
                        ProgressView()
                    } else if locked {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.subtleInk)
                    } else {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(starting != nil)
        .accessibilityHint(locked ? "Requires Twofold Premium" : "")
    }

    private func start(_ difficulty: SudokuDifficulty) {
        starting = difficulty
        Task {
            defer { starting = nil }
            do {
                let session = try await BackendService.startSudokuSession(difficulty: difficulty)
                route = session.sessionID
            } catch {
                errorMessage = "Couldn't start that puzzle. \(error.localizedDescription)"
            }
        }
    }
}

extension SudokuDifficulty {
    /// The two hardest are Premium — the same split the RPC enforces.
    var requiresPremium: Bool { self == .hard || self == .expert }

    var blurb: String {
        switch self {
        case .easy: "A gentle one. Most of the grid is already filled in."
        case .medium: "The usual weeknight puzzle."
        case .hard: "Fewer numbers to start from. Expect to use notes."
        case .expert: "Barely any givens. This one takes a while."
        }
    }
}
