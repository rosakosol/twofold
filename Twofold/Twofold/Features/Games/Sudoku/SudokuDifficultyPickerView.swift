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
    @State private var stats: SudokuStats?

    /// Seeds the table so previews and screenshots can show a real history without two people
    /// having to go and play one. `loadStats()` leaves whatever is here if its fetch fails, which
    /// is what keeps a seeded value on screen with no network.
    init(stats: SudokuStats? = nil) {
        _stats = State(initialValue: stats)
    }

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("The same grid on both your phones. Solve it apart, compare when you're done.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)

                if let stats, stats.hasAnything, stats.head2HeadTotal > 0 {
                    headToHead(stats)
                }

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
        // Reloaded every time the screen appears, not just once: finishing a puzzle and coming
        // back here is exactly when the numbers have changed.
        .task { await loadStats() }
    }

    /// The running record, across every puzzle both of them finished.
    private func headToHead(_ stats: SudokuStats) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Text("HEAD TO HEAD")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Theme.subtleInk)

                HStack(spacing: Theme.Spacing.lg) {
                    tally(String(stats.myWins), label: "You", isLeading: stats.myWins > stats.partnerWins)
                    if stats.ties > 0 {
                        tally(String(stats.ties), label: "Drawn", isLeading: false)
                    }
                    tally(
                        String(stats.partnerWins),
                        label: appModel.partner.name,
                        isLeading: stats.partnerWins > stats.myWins
                    )
                }

                Text("\(stats.head2HeadTotal) \(stats.head2HeadTotal == 1 ? "puzzle" : "puzzles") you've both finished")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tally(_ value: String, label: String, isLeading: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLeading ? Theme.leafGreenText : Theme.ink)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Both best times for one difficulty, or nothing at all if neither has played it — an
    /// untouched row says what it needs to by having no numbers, without a line of dashes.
    @ViewBuilder
    private func bestTimes(_ difficulty: SudokuDifficulty) -> some View {
        if let row = stats?.rows.first(where: { $0.difficulty == difficulty }), !row.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                bestTime(row.myBest, name: "You", solved: row.mySolved)
                Text("·").foregroundStyle(Theme.subtleInk)
                bestTime(row.partnerBest, name: appModel.partner.name, solved: row.partnerSolved)
            }
            .font(.caption)
        }
    }

    private func bestTime(_ elapsed: TimeInterval?, name: String, solved: Int) -> some View {
        // "—" rather than an omitted name: which of the two has not played this difficulty is
        // itself the interesting part, and dropping their side would read as a layout bug.
        Text("\(name) \(elapsed.map(SudokuComparison.clockText) ?? "—")")
            .foregroundStyle(elapsed == nil ? Theme.subtleInk : Theme.ink)
            .lineLimit(1)
            .accessibilityLabel(
                elapsed.map { "\(name), best \(SudokuComparison.clockText($0)), \(solved) solved" }
                    ?? "\(name), none solved"
            )
    }

    private func loadStats() async {
        guard let stats = try? await BackendService.fetchSudokuSolves() else { return }
        self.stats = SudokuStats.build(
            solves: stats,
            myID: appModel.currentUser.id,
            partnerID: appModel.partner.id
        )
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
                        bestTimes(difficulty)
                            .padding(.top, Theme.Spacing.xs)
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

#Preview("With a history") {
    // The numbers this screen exists to show only appear after two people have finished several
    // puzzles between them, which is not something a preview can wait for.
    let me = UUID(), partner = UUID()
    var solves: [SudokuSolve] = []
    func add(_ difficulty: SudokuDifficulty, mine: TimeInterval, theirs: TimeInterval?) {
        let session = UUID()
        solves.append(SudokuSolve(sessionID: session, difficulty: difficulty, responderID: me, elapsed: mine))
        if let theirs {
            solves.append(SudokuSolve(sessionID: session, difficulty: difficulty, responderID: partner, elapsed: theirs))
        }
    }
    add(.easy, mine: 221, theirs: 242)
    add(.easy, mine: 195, theirs: 260)
    add(.easy, mine: 240, theirs: 198)
    add(.medium, mine: 435, theirs: 408)
    add(.medium, mine: 520, theirs: 511)
    add(.hard, mine: 862, theirs: nil)

    return NavigationStack {
        SudokuDifficultyPickerView(
            stats: SudokuStats.build(solves: solves, myID: me, partnerID: partner)
        )
    }
    .environment(AppModel())
}

#Preview("Nothing played yet") {
    NavigationStack { SudokuDifficultyPickerView(stats: nil) }
        .environment(AppModel())
}
