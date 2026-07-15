//
//  TriviaBattleGameView.swift
//  Twofold
//
//  Competitive 5-question multiple choice quiz. Each partner answers all their own rounds
//  independently, at their own pace — results (including who got what right) only reveal once
//  both partners have answered every round (see `GameSessionStore.isRevealed`).
//

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
    @Environment(\.popToGamesRoot) private var popToGamesRoot
    @State private var store = GameSessionStore()
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var hapticTrigger = false
    @State private var showingNoMailAppAlert = false
    @State private var showingLeaveConfirm = false

    private var myID: UUID { appModel.currentUser.id }
    private var partnerID: UUID { appModel.partner.id }
    /// Gates the custom back button/leave-confirmation to the actual round-answering phase —
    /// false while loading, errored, already abandoned, or fully revealed. Also true while
    /// revisiting a round via "Edit My Answers" even though the session itself is still
    /// `completed` (`viewingRoundNumber` set — see `GameSessionStore.beginEditingAnswers()`), so
    /// that case gets the same in-round back behavior as live play rather than the results
    /// screen's "pop to hub" one below.
    private var isActivelyPlaying: Bool {
        !store.isLoading && store.errorMessage == nil && store.session?.status != .abandoned
            && (!store.isRevealed || store.viewingRoundNumber != nil)
    }
    /// The actual "completed game screen" — fully revealed and not mid-edit. Its back button
    /// pops straight to the Games hub root instead of one level, see `popToGamesRoot`.
    private var isShowingResults: Bool { store.isRevealed && store.viewingRoundNumber == nil }
    private var resolvedTopic: GameTopic? { topic.flatMap(GameTopic.init(rawValue:)) }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = store.errorMessage {
                GameErrorState(message: errorMessage)
            } else if let session = store.session, session.status == .abandoned {
                GameAbandonedState()
            } else if isShowingResults {
                GameResultsView(
                    gameType: .triviaBattle, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
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
                    pendingSyncCount: store.pendingSyncCount
                )
            }
        }
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
            if isActivelyPlaying {
                ToolbarItem(placement: .topBarLeading) {
                    GameBackButton(action: handleBack)
                }
            } else if isShowingResults {
                ToolbarItem(placement: .topBarLeading) {
                    GameBackButton(action: popToGamesRoot)
                }
            }
            // Not offered once results are showing — GameResultsView has its own toolbar
            // (Edit My Answers / Reset Game / support menu) for the post-completion case.
            if !store.isRevealed {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        SupportMenuItems(userID: myID, context: "\(GameType.triviaBattle.displayName) — session \(sessionID.uuidString)", showingNoMailAppAlert: $showingNoMailAppAlert)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(isActivelyPlaying || isShowingResults)
        .interactivePopGestureDisabled(isActivelyPlaying || isShowingResults)
        .noMailAppAlert(isPresented: $showingNoMailAppAlert)
        .gameLeaveConfirmation(isPresented: $showingLeaveConfirm) { Task { await leaveGame() } }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
            if isConnected, !wasConnected { Task { await store.syncPendingResponses() } }
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
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
                            PillBadge(text: resolvedTopic.displayName, tint: resolvedTopic.color)
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

    private func answerOptions(round: GameSessionRound, question: TriviaQuestion) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    let style = Self.optionStyles[index % Self.optionStyles.count]
                    let previousAnswer = store.myResponse(for: round, myID: myID)?.answerValue
                    let wasPreviouslyChosen = previousAnswer == option
                    // Revisiting an already-answered question via the back button — every other
                    // option desaturates so the one actually picked stands out clearly, instead
                    // of all four looking equally "live" the way a fresh, unanswered question does.
                    let shouldDim = previousAnswer != nil && !wasPreviouslyChosen
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
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value, isCorrect: isCorrect)
            isSubmitting = false
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
        } else if store.isRevealed {
            // Editing an already-completed session with nothing before round 1 — nothing here
            // is actually in danger of being lost (every answer's already saved), so this just
            // exits editing back to the results screen rather than the leave-confirmation below.
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
