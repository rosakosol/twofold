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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store: WordSearchGameStore
    @State private var confirmingAbandon = false
    @State private var abandonFailed: String?
    @State private var isSendingReminder = false
    @State private var showingReminderSent = false
    /// Toggled when both results exist. Toggled rather than set, because `ConfettiBurstView`
    /// animates on any *change* of its trigger.
    @State private var confettiTrigger = false
    @State private var celebratedSession: UUID?

    init(sessionID: UUID) {
        _store = State(initialValue: WordSearchGameStore(sessionID: sessionID))
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
                content
            }

            // Outside the switch so it is mounted before the grid loads — it animates on a change
            // of its trigger, and a burst view that appeared already-true would never see one.
            ConfettiBurstView(trigger: confettiTrigger)
        }
        .navigationTitle(GameType.wordSearch.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Its own back button, not the system one.
        //
        // A notification opens a game through `RootView`'s `fullScreenCover`, which wraps it in a
        // fresh `NavigationStack` — and at the root of a fresh stack there is nothing to pop, so
        // the system back button is simply absent. That left every one of these screens with no
        // way out at all: the only exit was force-quitting the app. `dismiss()` is right in both
        // contexts, popping when pushed and closing the cover when it is the root, which is what
        // the four deck games have always done.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameBackButton(action: { dismiss() })
            }
        }
        .toolbar {
            // Only while there are words left. Once the grid is cleared the thing you want is the
            // comparison, and abandoning would throw away a result that is already submitted.
            if store.play?.isComplete == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmingAbandon = true
                        } label: {
                            Label("Abandon this grid", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Abandon this grid?", isPresented: $confirmingAbandon, titleVisibility: .visible) {
            Button("Abandon", role: .destructive) { abandon() }
            Button("Keep looking", role: .cancel) {}
        } message: {
            // Named plainly because the session is the couple's, not this player's:
            // `start_word_search_session` resumes per couple and theme, so one grid is shared
            // between them and ending it ends it for both.
            Text(
                appModel.hasCouple
                ? "This ends it for both of you — \(appModel.partner.name)'s progress on this grid goes too. You'll be able to start a new one straight away."
                : "You'll be able to start a new grid straight away."
            )
        }
        .alert("Couldn't abandon", isPresented: .constant(abandonFailed != nil)) {
            Button("OK") { abandonFailed = nil }
        } message: {
            Text(abandonFailed ?? "")
        }
        .alert("Reminder Sent", isPresented: $showingReminderSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(appModel.partner.name) has been told their grid is waiting.")
        }
        .task(id: store.sessionID) {
            await store.load()
            store.startClock()
        }
        // Its own task: `subscribeRealtime()` loops until cancelled, so folding it into the one
        // above would mean the grid waited on a stream that never ends.
        .task(id: store.sessionID) { await store.subscribeRealtime() }
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
        .onDisappear {
            store.stopClock()
            store.stopRealtime()
        }
        .onChange(of: scenePhase) { _, phase in
            // The clock measures time at the grid, so backgrounding stops it.
            if phase == .active { store.startClock() } else { store.stopClock() }
        }
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
                Text(theme.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.skyBlueText)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.cardBackground, in: Capsule())
            }
            Spacer()
            Text("\(play.found.count)/\(play.totalCount)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Label(PuzzleClock.text(play.elapsed), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
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
                        .foregroundStyle(isFound ? Theme.subtleInk : Theme.ink)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            isFound ? Theme.leafGreen.opacity(0.15) : Theme.cardBackground,
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

            // Outside the card: `GameReminderButton` is filled with `Theme.cardBackground` so it
            // reads as raised against the page, which is the one colour it would disappear into
            // inside a `SectionCard`. Same placement the deck games use.
            if appModel.hasCouple {
                GameReminderButton(isSending: isSendingReminder, action: remindPartner)
            }
        }
    }

    private func clearedSummary(play: WordSearchPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)

                Text("Cleared in \(PuzzleClock.text(play.elapsed))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)

                if appModel.hasCouple {
                    Text("Your time is saved. You'll see how it compares once \(appModel.partner.name) has cleared theirs.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your time is saved.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Ends the shared session and goes back to the theme list, where starting the same theme now
    /// gets a genuinely new grid rather than this one again.
    private func abandon() {
        let id = store.sessionID
        store.stopClock()
        Task {
            do {
                try await BackendService.abandonGameSession(id: id)
                // The device's own copy goes too, or the grid sits in the cache forever — harmless,
                // but it is the abandoned puzzle's last trace and nothing will ask for it again.
                if let me = BackendService.currentUserID {
                    PuzzleProgressCache.wordSearch.remove(sessionID: id, responderID: me)
                }
                dismiss()
            } catch {
                abandonFailed = error.localizedDescription
            }
        }
    }

    /// The same `gameReminder` push the other games send — it is the identical situation, and a
    /// second notification type saying the same thing is a second thing to keep in step.
    private func remindPartner() {
        isSendingReminder = true
        Task {
            await BackendService.notifyPartner(
                event: .gameReminder,
                detail: store.theme.map { "\($0.displayName) Word Search" } ?? GameType.wordSearch.displayName,
                sessionID: store.sessionID,
                gameType: .wordSearch
            )
            isSendingReminder = false
            showingReminderSent = true
        }
    }
}
