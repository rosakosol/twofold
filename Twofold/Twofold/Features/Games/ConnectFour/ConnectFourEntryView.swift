//
//  ConnectFourEntryView.swift
//  Twofold
//
//  Connect 4's front door. No decks, no difficulties, no themes — one board per couple, so the only
//  thing to decide is whether to open it.
//
//  It exists rather than the hub card pushing straight in because starting is a round trip that can
//  refuse, and because a session should be created by somebody deciding to play rather than by
//  somebody browsing past. Tapping a card is not a decision to start a game the partner will then
//  be notified about.
//

import SwiftUI

struct ConnectFourEntryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isStarting = false
    @State private var route: StartedConnectFour?
    @State private var errorMessage: String?
    @State private var records: [GameRecord] = []
    @State private var showingPaywall = false
    @State private var history: [BackendService.ConnectFourHistoryEntry] = []

    /// Premium since 20261111000700, when chess was withdrawn and this took its place as a named
    /// Premium game. The server refuses too — `start_connect_four_session` raises
    /// `connect_four_requires_premium` — so this only decides what the screen offers, never
    /// whether a board can actually be created.
    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("One board between you. Take turns dropping a disc — first to get four in a row, in any direction, wins.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // No bests for a board game: there is no time or score to keep, only the record.
                GameRecordCard(
                    records: records.filter { $0.gameType == .connectFour },
                    partnerName: appModel.partner.name,
                    formatBest: nil
                )

                howItLooks

                Text("Played a move at a time, whenever you each get to it — there's no clock. You'll be told when it's your turn.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let unseen = unseenResult {
                    lastResultCard(unseen)
                }

                if isPremium {
                    startButton
                } else {
                    premiumGate
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                previousGames
            }
            .padding(Theme.Spacing.md)
        }
        .background(ScreenBackground())
        .navigationTitle(GameType.connectFour.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Reloaded every time the screen appears: coming back after a game is exactly when the
        // record has changed.
        .task {
            async let fetchedRecords = BackendService.fetchGameRecords()
            async let fetchedHistory = try? BackendService.fetchConnectFourHistory()
            records = await fetchedRecords
            history = await fetchedHistory ?? history
        }
        .navigationDestination(item: $route) { started in
            ConnectFourGameView(sessionID: started.id)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    /// A finished board rather than an empty one. "Four in a row" is quicker to see than to read,
    /// and an empty grid would be a picture of nothing.
    private var howItLooks: some View {
        ConnectFourBoardView(
            board: ConnectFourBoard(droppedColumns: [3, 2, 4, 2, 5, 1, 6]),
            myDisc: .first,
            isInteractive: false,
            onDrop: { _ in }
        )
        .accessibilityHidden(true)
    }

    /// Shown in place of Play, not instead of the screen.
    ///
    /// The board above stays visible deliberately: somebody deciding whether Premium is worth it
    /// should be able to see what they would be getting, and a screen that refused to render
    /// would only teach them the game is broken. Same reasoning the games hub gives for opening a
    /// gated game's entry screen at all.
    private var premiumGate: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Connect 4 is part of Premium")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("One board between you, played a move at a time.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("See Premium") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: Theme.Spacing.xs) {
                if isStarting { ProgressView().controlSize(.small).tint(.white) }
                // Deliberately not "Start a game": only the server knows whether one is already
                // going, and a button promising a new board that hands back a half-played one is a
                // small lie told at the worst moment.
                Text("Play")
                    .font(.headline)
            }
        }
        .buttonStyle(.twofoldPrimary)
        .disabled(isStarting)
    }

    // MARK: - Results

    /// The newest game, if it has ended with a result this phone hasn't shown yet.
    ///
    /// Reported: a game that ended while you were elsewhere vanished. Play hands back the current
    /// board or starts a new one, so the finished game was never on screen again, and who won went
    /// unseen. Now it waits here until it has been looked at.
    private var unseenResult: BackendService.ConnectFourHistoryEntry? {
        guard let latest = history.first, latest.status == .completed, latest.outcome != nil,
              !ConnectFourSeenResults.hasSeen(latest.id)
        else { return nil }
        return latest
    }

    private func lastResultCard(_ entry: BackendService.ConnectFourHistoryEntry) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Your last game finished")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(outcomeText(entry))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("See the board") { route = StartedConnectFour(id: entry.id) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Every recent board: when it ended and how. Tapping one opens it, finished, with its result.
    @ViewBuilder
    private var previousGames: some View {
        let finished = history.filter(\.isFinished)
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Previous games")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Theme.Spacing.sm)
                SectionCard {
                    VStack(spacing: 0) {
                        ForEach(Array(finished.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            Button { open(entry) } label: { historyRow(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: BackendService.ConnectFourHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: outcomeIcon(entry))
                .foregroundStyle(entry.winnerID == BackendService.currentUserID ? Theme.success : Theme.textSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcomeText(entry))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(entry.endedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Image(systemName: isPremium ? "chevron.right" : "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func outcomeText(_ entry: BackendService.ConnectFourHistoryEntry) -> String {
        guard let outcome = entry.outcome else { return "Ended with no winner" }
        if outcome == "win", let winner = entry.winnerID {
            return winner == BackendService.currentUserID ? "You won" : "\(appModel.partner.name) won"
        }
        return "A draw"
    }

    private func outcomeIcon(_ entry: BackendService.ConnectFourHistoryEntry) -> String {
        guard entry.outcome != nil else { return "flag.slash" }
        return entry.winnerID == nil ? "equal.circle" : "trophy.fill"
    }

    /// Results are Premium, like Connect 4 itself and like Word Guess's: on Plus the row says how it
    /// went, and tapping it offers Premium.
    private func open(_ entry: BackendService.ConnectFourHistoryEntry) {
        if isPremium {
            route = StartedConnectFour(id: entry.id)
        } else {
            showingPaywall = true
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                let session = try await BackendService.startConnectFourSession()
                route = StartedConnectFour(id: session.sessionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StartedConnectFour: Identifiable, Hashable {
    let id: UUID
}

/// Which finished games this phone has shown, so the entry screen offers a result until it has
/// been seen and not after. On the device rather than the server: "seen" is about this screen,
/// and the worst a lost record can do is offer a result once more. Cleared on sign-out.
enum ConnectFourSeenResults {
    static let key = "connectFour.seenResults"

    static func hasSeen(_ sessionID: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(sessionID.uuidString)
    }

    static func markSeen(_ sessionID: UUID) {
        var seen = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !seen.contains(sessionID.uuidString) else { return }
        seen.append(sessionID.uuidString)
        // Only the newest matter: the card only ever asks about the latest game.
        UserDefaults.standard.set(Array(seen.suffix(50)), forKey: key)
    }
}

#Preview {
    NavigationStack { ConnectFourEntryView() }
        .environment(AppModel())
}
