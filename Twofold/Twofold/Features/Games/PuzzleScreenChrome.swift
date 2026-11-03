//
//  PuzzleScreenChrome.swift
//  Twofold
//
//  What the Sudoku, Word Guess and Word Search screens share around their boards (GAME-15): the
//  back button, the abandon menu, loading and realtime, the clock following the app in and out of
//  the foreground, retrying a result on reconnect, the pending-result banner, the share sheet and
//  the reminder alert. Each screen used to carry its own copy of all of it.
//

import SwiftUI

/// What a puzzle store offers the screen around it.
@MainActor
protocol PuzzleScreenStore: AnyObject, Observable {
    var sessionID: UUID { get }
    var link: PuzzleResultLink { get }
    /// Whether the abandon menu is offered: only while the puzzle is loaded and unfinished. Once it
    /// is finished the thing you want is the comparison, and abandoning would throw away a result
    /// that is already submitted.
    var canAbandon: Bool { get }
    func load() async
    func startClock()
    func stopClock()
    func retryPendingResult() async
    /// Ends the puzzle for both partners.
    func abandonSession() async throws
}

/// The words a puzzle uses for abandoning itself — "this puzzle", "this grid", "this word".
struct PuzzleAbandonCopy {
    let menuItem: String
    let title: String
    let keepPlaying: String
    /// Named plainly because the session is the couple's, not this player's: ending it ends it for
    /// both.
    let message: String
}

extension PuzzleAbandonCopy {
    /// Sudoku's. `partnerName` is nil for someone playing alone, who has no partner whose
    /// progress could go with it.
    static func sudoku(partnerName: String?, difficulty: SudokuDifficulty?) -> PuzzleAbandonCopy {
        // "a new hard puzzle", or "a new puzzle" — never "a new  puzzle".
        let next = difficulty.map { "new \($0.displayName.lowercased()) puzzle" } ?? "new puzzle"
        let startAgain = "You'll be able to start a \(next) straight away."
        return PuzzleAbandonCopy(
            menuItem: "Abandon this puzzle",
            title: "Abandon this puzzle?",
            keepPlaying: "Keep playing",
            // `start_sudoku_session` resumes per couple, so one grid is shared between them.
            // Someone abandoning what they think is their own copy would otherwise wipe out a
            // partner's half-finished solve with no warning. Alone there is no one else's
            // progress to lose, and naming the placeholder "Partner" invented one (GAME-9).
            message: partnerName.map { "This ends it for both of you — \($0)'s progress on this grid goes too. \(startAgain)" }
                ?? startAgain
        )
    }
}

extension View {
    /// The shared chrome for a puzzle screen. `share` drives the share sheet; a screen with nothing
    /// to share passes `.constant(nil)`.
    func puzzleScreenChrome<Store: PuzzleScreenStore>(
        store: Store,
        abandon: PuzzleAbandonCopy,
        reminderSentMessage: String,
        share: Binding<GameResultShareData?>
    ) -> some View {
        modifier(PuzzleScreenChrome(store: store, abandonCopy: abandon, reminderSentMessage: reminderSentMessage, share: share))
    }
}

private struct PuzzleScreenChrome<Store: PuzzleScreenStore>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    let store: Store
    let abandonCopy: PuzzleAbandonCopy
    let reminderSentMessage: String
    @Binding var share: GameResultShareData?

    @State private var confirmingAbandon = false
    @State private var abandonFailed: String?

    func body(content: Content) -> some View {
        @Bindable var link = store.link
        content
            // Its own back button, not the system one.
            //
            // A notification opens a game through `RootView`'s `fullScreenCover`, which wraps it
            // in a fresh `NavigationStack` — and at the root of a fresh stack there is nothing to
            // pop, so the system back button is simply absent. That left every one of these
            // screens with no way out at all: the only exit was force-quitting the app.
            // `dismiss()` is right in both contexts, popping when pushed and closing the cover when
            // it is the root, which is what the four deck games have always done.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GameBackButton(action: { dismiss() })
                }
            }
            .toolbar {
                if store.canAbandon {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                confirmingAbandon = true
                            } label: {
                                Label(abandonCopy.menuItem, systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
                    }
                }
            }
            .confirmationDialog(abandonCopy.title, isPresented: $confirmingAbandon, titleVisibility: .visible) {
                Button("Abandon", role: .destructive) { abandon() }
                Button(abandonCopy.keepPlaying, role: .cancel) {}
            } message: {
                Text(abandonCopy.message)
            }
            .alert("Couldn't abandon", isPresented: Binding(get: { abandonFailed != nil }, set: { if !$0 { abandonFailed = nil } })) {
                Button("OK") { abandonFailed = nil }
            } message: {
                Text(abandonFailed ?? "")
            }
            .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) {
                if let share {
                    GameShareSheet(data: share)
                }
            }
            .alert(
                link.reminderResult == .failed ? "Couldn't send reminder" : "Reminder sent",
                isPresented: Binding(get: { link.reminderResult != nil }, set: { if !$0 { link.reminderResult = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                if link.reminderResult == .failed {
                    Text("Check your connection and try again.")
                } else {
                    Text(reminderSentMessage)
                }
            }
            // Keyed on the session rather than on the view's lifetime: Sudoku's "play another"
            // replaces its store in place, and a plain `.task` would leave both of these running
            // against the puzzle that is no longer on screen — the old clock still ticking, the old
            // realtime stream still listening. `.task(id:)` cancels and restarts them on the swap.
            .task(id: store.sessionID) {
                await store.load()
                store.startClock()
            }
            // Its own task: `subscribeRealtime()` loops until cancelled, so folding it into the one
            // above would mean the board waited on a stream that never ends.
            .task(id: store.sessionID) { await store.link.subscribeRealtime() }
            .onDisappear {
                store.stopClock()
                store.link.stopRealtime()
            }
            .onChange(of: scenePhase) { _, phase in
                // The clock measures time at the board, so backgrounding stops it. Without this a
                // puzzle left open in a pocket would report an afternoon's solve.
                if phase == .active { store.startClock() } else { store.stopClock() }
                if phase == .active { Task { await store.retryPendingResult() } }
            }
            .onChange(of: NetworkMonitor.shared.isConnected) { _, isConnected in
                // The result may have been waiting on exactly this. `GameResponseOutbox` sends it
                // too, from `RootView`'s reconnect; whichever gets there first, the other finds
                // nothing left to send.
                if isConnected { Task { await store.retryPendingResult() } }
            }
            .safeAreaInset(edge: .top) {
                if store.link.isPending {
                    OfflineGameBanner(isConnected: NetworkMonitor.shared.isConnected, pendingCount: 1, isResult: true)
                }
            }
    }

    /// Ends the shared session and goes back to where the puzzle was chosen, where starting the
    /// same one now gets a genuinely new board rather than this one again.
    private func abandon() {
        Task {
            do {
                try await store.abandonSession()
                dismiss()
            } catch {
                abandonFailed = error.localizedDescription
            }
        }
    }
}
