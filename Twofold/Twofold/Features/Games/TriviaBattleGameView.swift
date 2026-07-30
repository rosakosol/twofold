//
//  TriviaBattleGameView.swift
//  Twofold
//
//  Competitive 5-question multiple choice quiz. Each partner answers all their own rounds
//  independently, at their own pace — results (including who got what right) only reveal once
//  both partners have answered every round (see `GameSessionStore.isRevealed`).
//

import PostHog
import SwiftUI

struct TriviaBattleGameView: View {
    let sessionID: UUID
    /// Overrides the generic "Trivia Battle" nav title — set to the deck's own title when
    /// reached via DeckEntryView, so the title doesn't shift once play actually starts.
    var title: String? = nil
    /// The deck's raw `GameTopic` string, nil for a non-deck session — shown as the same badge
    /// style the deck's own card already uses (see `DeckCardRow`'s `showsTopicPill`).
    var topic: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var hapticTrigger = false
    @State private var showingReportSheet = false
    @State private var showingLeaveConfirm = false
    /// The option just tapped, shown via local state rather than waiting on
    /// `store.myResponse(...)` to reflect it — `store.submit` synchronously updates
    /// `GameSessionStore.responses`, which is also what `displayedRound(myID:)` (and so this
    /// round's `.id()`) is derived from, so without this the round-advance transition would tear
    /// this view down before the tapped option's checkmark/highlight below ever got a frame to
    /// render. Mirrors `SwipeChoiceCard.fly()`'s deferred-action pattern, same underlying reason.
    ///
    /// Tagged with the round it was chosen for — this is held for a beat *after* `store.submit`
    /// has already advanced `displayedRound` to the *next* round (see `submit(round:value:isCorrect:)`),
    /// so a bare `String?` briefly compared the previous round's chosen text against the new
    /// round's completely different options: never equal, so every option in the fresh round
    /// evaluated as "answered, but not this one" and dimmed for a frame before snapping back to
    /// full color once this cleared. Checking the round id too means a stale value from the
    /// previous round is simply ignored once the new one mounts.
    @State private var chosenOption: (roundID: UUID, value: String)?

    private var myID: UUID { appModel.currentUser.id }
    private var partnerID: UUID { appModel.partner.id }
    /// Gates the custom back button/leave-confirmation to still actively answering my own
    /// rounds for the first time — false once I've answered every round, whether or not my
    /// partner has too (see `isDoneWithMyRounds` below). Also true while revisiting a round via
    /// "Edit My Answers" (`viewingRoundNumber` set — see `GameSessionStore.beginEditingAnswers()`),
    /// so that case gets the same in-round back behavior as live play.
    private var isActivelyPlaying: Bool {
        !store.isLoading && store.errorMessage == nil && store.session?.status != .abandoned
            && (!store.hasAnsweredAllRounds(myID: myID) || store.viewingRoundNumber != nil)
    }
    /// Covers both "I'm done, waiting on my partner" (GameCompletionView) and "we're both done"
    /// (GameResultsView) — the two screens where back should pop straight to the Games hub
    /// instead of revisiting a round.
    private var isDoneWithMyRounds: Bool {
        !store.isLoading && store.errorMessage == nil && store.session?.status != .abandoned
            && store.hasAnsweredAllRounds(myID: myID) && store.viewingRoundNumber == nil
    }
    private var resolvedTopic: GameTopic? { topic.flatMap(GameTopic.init(rawValue:)) }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = store.errorMessage {
                GameErrorState(message: errorMessage)
            } else if let session = store.session, session.status == .abandoned {
                GameAbandonedState()
            } else if store.isRevealed && store.viewingRoundNumber == nil {
                GameResultsView(
                    gameType: .triviaBattle, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }, title: title
                )
            } else if let round = store.displayedRound(myID: myID), case let .trivia(question)? = store.content(for: round) {
                roundView(round: round, question: question)
                    .id(round.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: round.id)
            } else {
                GameCompletionView(
                    partnerName: appModel.partner.name,
                    partnerProgress: store.partnerProgress(partnerID: partnerID),
                    isSendingReminder: isSendingReminder,
                    onSendReminder: { Task { await sendReminder() } },
                    onPlayAnother: { dismiss() },
                    onEditAnswers: { store.beginEditingAnswers() },
                    pendingSyncCount: store.pendingSyncCount,
                    deckID: store.session?.deckID
                )
            }
        }
        // Without this, swapping branches (e.g. `ProgressView` → `GameResultsView` the instant a
        // session loads already-revealed, via History/a deep link) picks up SwiftUI's default
        // fade/insertion transition — which made the full-bleed background below appear briefly
        // undersized before snapping to full width. `.identity` makes every branch without its
        // own explicit transition swap in instantly; `roundView`'s own `.transition(.scale...)`
        // below is more specific and still wins for that branch.
        .transition(.identity)
        .safeAreaInset(edge: .top) {
            if store.pendingSyncCount > 0 {
                OfflineGameBanner(isConnected: NetworkMonitor.shared.isConnected, pendingCount: store.pendingSyncCount)
            }
        }
        // Pinned against the round-transition spring below via `.transaction { $0.animation = nil }`
        // — without it, the full-bleed background was observed interpolating its own width
        // alongside that animation instead of staying static.
        .background(Theme.backgroundGradient.ignoresSafeArea().transaction { $0.animation = nil })
        .navigationTitle(title ?? GameType.triviaBattle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A custom `.principal` item, not just relying on `.navigationTitle` above — an
            // inline nav title is always clamped to one line with a trailing ellipsis, which cut
            // off longer deck titles. This wraps to 2 lines instead; `.navigationTitle` stays
            // (unused visually while this is present) purely so a screen pushed from here still
            // gets a sensible back-button label.
            ToolbarItem(placement: .principal) {
                Text(title ?? GameType.triviaBattle.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if isActivelyPlaying {
                ToolbarItem(placement: .topBarLeading) {
                    GameBackButton(action: handleBack)
                }
            } else if isDoneWithMyRounds {
                ToolbarItem(placement: .topBarLeading) {
                    GameBackButton(action: { dismiss() })
                }
            }
            // Not offered once results are showing — GameResultsView has its own toolbar
            // (Edit My Answers / Reset Game / support menu) for the post-completion case.
            if !store.isRevealed {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ReportProblemMenuItem(showingReportSheet: $showingReportSheet)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(isActivelyPlaying || isDoneWithMyRounds)
        .interactivePopGestureDisabled(isActivelyPlaying || isDoneWithMyRounds)
        .gameIssueReportSheet(isPresented: $showingReportSheet) {
            store.gameIssueContext(gameType: .triviaBattle, deckTitle: title, myID: myID)
        }
        .gameLeaveConfirmation(isPresented: $showingLeaveConfirm) { Task { await leaveGame() } }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
            if isConnected, !wasConnected { Task { await store.syncPendingResponses() } }
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .postHogScreenView("Games: Trivia Battle")
    }

    // MARK: - Round

    /// Kahoot-style: a fixed color+shape per grid position, not tied to the answer's content —
    /// same reasoning as the old numbered-keycap emoji (answer text is free-form, so the marker
    /// has to be positional), just bolder.
    private static let optionStyles: [(color: Color, icon: String)] = [
        (Theme.heartRed, "triangle.fill"),
        (Theme.skyBlue, "diamond.fill"),
        (.orange, "circle.fill"),
        (Theme.leafGreen, "square.fill"),
    ]

    private func roundView(round: GameSessionRound, question: TriviaQuestion) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Question \(round.roundNumber) of \(store.rounds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                        if let resolvedTopic {
                            PillBadge(text: resolvedTopic.displayName, tint: resolvedTopic.color, isNeutral: true)
                        }
                        Text(question.question)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                        // Shown when revisiting an already-answered question via the back
                        // button — the option itself also gets a checkmark badge below, this
                        // just states it plainly up top too.
                        if let previousAnswer = store.myResponse(for: round, myID: myID)?.answerValue {
                            Text(previousAnswer.isEmpty ? "You skipped this one" : "You chose: \(previousAnswer)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.leafGreen)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    answerOptions(round: round, question: question)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
        }
    }

    /// Content is authored with `correct_answer` frequently landing first in `options` — rendering
    /// that raw order would make the first tile the correct pick far more often than chance.
    /// Order is re-derived from `round.id` (not shuffled inline) so it stays stable across
    /// re-renders/edits of the same round instead of jumping around as the user interacts with it.
    private func orderedOptions(round: GameSessionRound, question: TriviaQuestion) -> [String] {
        let seed = round.id.uuidString
        return question.options.sorted { a, b in stableHash(seed + a) < stableHash(seed + b) }
    }

    private func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash << 5 &+ hash) &+ UInt64(byte) }
        return hash
    }

    private func answerOptions(round: GameSessionRound, question: TriviaQuestion) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                ForEach(Array(orderedOptions(round: round, question: question).enumerated()), id: \.offset) { index, option in
                    let style = Self.optionStyles[index % Self.optionStyles.count]
                    let previousAnswer = store.myResponse(for: round, myID: myID)?.answerValue
                    // `chosenOption` wins while a submit is being held for *this* round (see its
                    // own doc comment) — `previousAnswer` only catches up once the deferred
                    // `store.submit` below actually runs, and is also what applies once a stale
                    // `chosenOption` from the *previous* round no longer matches `round.id`.
                    let effectiveAnswer = (chosenOption?.roundID == round.id ? chosenOption?.value : nil) ?? previousAnswer
                    let wasPreviouslyChosen = effectiveAnswer == option
                    // Revisiting an already-answered question via the back button — every other
                    // option desaturates so the one actually picked stands out clearly, instead
                    // of all four looking equally "live" the way a fresh, unanswered question does.
                    let shouldDim = effectiveAnswer != nil && !wasPreviouslyChosen
                    Button {
                        submit(round: round, value: option, isCorrect: option == question.correctAnswer)
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: style.icon)
                                .font(.title3)
                                .foregroundStyle(.white)
                            Text(option)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .padding(Theme.Spacing.sm)
                        .background(style.color, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .saturation(shouldDim ? 0 : 1)
                        .opacity(shouldDim ? 0.55 : 1)
                        .overlay(alignment: .topTrailing) {
                            if wasPreviouslyChosen {
                                ZStack {
                                    Circle().fill(.white)
                                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(style.color)
                                }
                                .frame(width: 22, height: 22)
                                .padding(6)
                            }
                        }
                        .overlay {
                            if wasPreviouslyChosen {
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(.white, lineWidth: 3)
                            }
                        }
                    }
                    .disabled(isSubmitting)
                }
            }

            SkipButton(isDisabled: isSubmitting) {
                submit(round: round, value: "", isCorrect: false)
            }
        }
    }

    // MARK: - Actions

    private func submit(round: GameSessionRound, value: String, isCorrect: Bool) {
        hapticTrigger.toggle()
        isSubmitting = true
        chosenOption = (round.id, value)
        Task {
            // Held briefly so the tapped option's checkmark/highlight actually gets a frame on
            // screen before `store.submit`'s optimistic update advances `displayedRound` and
            // tears this view down via its `.id(round.id)` transition — see `chosenOption`'s doc
            // comment.
            try? await Task.sleep(for: .seconds(0.35))
            await store.submit(roundNumber: round.roundNumber, answerValue: value, isCorrect: isCorrect)
            isSubmitting = false
            chosenOption = nil
        }
    }

    private func sendReminder() async {
        isSendingReminder = true
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.triviaBattle.displayName, sessionID: sessionID, gameType: .triviaBattle)
        isSendingReminder = false
    }

    private func handleBack() {
        if store.canGoBack(myID: myID) {
            store.goBack(myID: myID)
        } else if store.viewingRoundNumber != nil, store.hasAnsweredAllRounds(myID: myID) {
            // Editing (from either GameCompletionView or GameResultsView) with nothing before
            // round 1 — only reachable once every round is already answered, which is what
            // distinguishes this from genuinely live-playing and having stepped back to round 1
            // (viewingRoundNumber is non-nil in both cases). Nothing here is actually in danger
            // of being lost (every answer's already saved), so this just exits editing back to
            // whichever "I'm done" screen prompted it, rather than the leave-confirmation below.
            store.viewingRoundNumber = nil
        } else if store.hasAnsweredAnyRounds(myID: myID) {
            showingLeaveConfirm = true
        } else {
            // Nothing answered yet — nothing a confirmation would actually be protecting, so
            // just let them out.
            dismiss()
        }
    }

    private func leaveGame() async {
        if let sessionID = store.session?.id {
            try? await BackendService.abandonGameSession(id: sessionID)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TriviaBattleGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
