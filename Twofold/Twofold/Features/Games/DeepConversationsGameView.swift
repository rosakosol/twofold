//
//  DeepConversationsGameView.swift
//  Twofold
//
//  A guided conversation, not a competition — gentler copy/pacing than the other three games,
//  no scores or winners. Each partner writes a private initial response to every topic at their
//  own pace; once both are done, `GameResultsView` shows both sides side-by-side with
//  "Talked about" / "Come back later" marking for each topic.
//

import SwiftUI

struct DeepConversationsGameView: View {
    let sessionID: UUID
    /// Overrides the generic "Deep Conversation" nav title — set to the deck's own title when
    /// reached via DeckEntryView, so the title doesn't shift once play actually starts.
    var title: String? = nil
    /// The deck's raw `GameTopic` string, nil for a non-deck session — shown as the same badge
    /// style the deck's own card already uses (see `DeckCardRow`'s `showsTopicPill`).
    var topic: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var responseText = ""
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var showingNoMailAppAlert = false
    @State private var showingLeaveConfirm = false

    private var myID: UUID { appModel.currentUser.id }
    private var partnerID: UUID { appModel.partner.id }
    /// Also true while revisiting a round via "Edit My Answers" even though I've already
    /// answered every round — see `TriviaBattleGameView`'s identical property for the full
    /// reasoning.
    private var isActivelyPlaying: Bool {
        !store.isLoading && store.errorMessage == nil && store.session?.status != .abandoned
            && (!store.hasAnsweredAllRounds(myID: myID) || store.viewingRoundNumber != nil)
    }
    /// Covers both "I'm done, waiting on my partner" and "we're both done" — see
    /// `TriviaBattleGameView`'s identical property for the full reasoning.
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
                    gameType: .deepConversations, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
                )
            } else if let round = store.displayedRound(myID: myID), case let .deepConversation(topic)? = store.content(for: round) {
                roundView(round: round, topic: topic)
                    .onAppear { responseText = store.myResponse(for: round, myID: myID)?.answerValue ?? "" }
                    .onChange(of: round.id) { _, _ in
                        // Fires on every round change — forward progress and back-navigation
                        // alike — so this is the one place `responseText` gets (re)populated:
                        // empty for a fresh round, or the prior answer when revisiting one
                        // already answered.
                        responseText = store.myResponse(for: round, myID: myID)?.answerValue ?? ""
                    }
            } else {
                GameCompletionView(
                    partnerName: appModel.partner.name,
                    partnerProgress: store.partnerProgress(partnerID: partnerID),
                    isSendingReminder: isSendingReminder,
                    onSendReminder: { Task { await sendReminder() } },
                    onPlayAnother: { dismiss() },
                    myAnswersRecap: myAnswersRecap,
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
        // Pinned static regardless of any surrounding animated transaction — see the other 3
        // typed game views for why.
        .background(Theme.backgroundGradient.ignoresSafeArea().transaction { $0.animation = nil })
        .navigationTitle(title ?? GameType.deepConversations.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                        SupportMenuItems(userID: myID, context: "\(GameType.deepConversations.displayName) — session \(sessionID.uuidString)", showingNoMailAppAlert: $showingNoMailAppAlert)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(isActivelyPlaying || isDoneWithMyRounds)
        .interactivePopGestureDisabled(isActivelyPlaying || isDoneWithMyRounds)
        .noMailAppAlert(isPresented: $showingNoMailAppAlert)
        .gameLeaveConfirmation(isPresented: $showingLeaveConfirm) { Task { await leaveGame() } }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
            if isConnected, !wasConnected { Task { await store.syncPendingResponses() } }
        }
    }

    private func roundView(round: GameSessionRound, topic: DeepConversationTopic) -> some View {
        // Vertically centered like the other 3 typed game views (Trivia/This or That/More
        // Likely all already did this via the same GeometryReader + minHeight pattern) — this
        // one was left as a plain top-aligned ScrollView, so its content sat up against the nav
        // bar instead of centered in the available space.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Topic \(round.roundNumber) of \(store.rounds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                        if let resolvedTopic {
                            PillBadge(text: resolvedTopic.displayName, tint: resolvedTopic.color)
                        }
                        Text(topic.topic)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    responseInput(round: round)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
        }
    }

    private func responseInput(round: GameSessionRound) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Jot down a few private thoughts before you see each other's answers.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)

            TextEditor(text: $responseText)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            Button {
                submit(round: round, value: responseText.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            // On the daily question, an empty "Next" tap would otherwise be a skip in
            // everything but name — require real text there, same intent as hiding SkipButton
            // below.
            .disabled(isSubmitting || (store.session?.isDaily == true && responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            // The couple's one shared daily question is meant to always get a real answer from
            // both of you — every other Discuss deck stays skippable (content-safety
            // requirement, see SkipButton), this is the one deliberate exception.
            if store.session?.isDaily != true {
                SkipButton(isDisabled: isSubmitting) {
                    submit(round: round, value: "")
                }
            }
        }
    }

    private func submit(round: GameSessionRound, value: String) {
        isSubmitting = true
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value)
            // No manual `responseText` reset here — the `.onChange(of: round.id)` handler on the
            // round view above is the single source of truth for it, firing once `store.submit`
            // has moved on to whichever round comes next (a fresh one, or the previous one again
            // if the player was revisiting it — see GameSessionStore.advanceViewingCursorIfNeeded).
            isSubmitting = false
        }
    }

    private func sendReminder() async {
        isSendingReminder = true
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.deepConversations.displayName, sessionID: sessionID, gameType: .deepConversations)
        isSendingReminder = false
    }

    private func handleBack() {
        if store.canGoBack(myID: myID) {
            store.goBack(myID: myID)
        } else if store.viewingRoundNumber != nil, store.hasAnsweredAllRounds(myID: myID) {
            // Editing — only reachable once every round is already answered, which is what
            // distinguishes this from genuinely live-playing and having stepped back to round 1
            // (viewingRoundNumber is non-nil in both cases). Exits editing back to whichever
            // "I'm done" screen prompted it, rather than the leave-confirmation below.
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

    /// My own private responses so far — safe to show to me alone even before the session
    /// reveals, unlike the other games where seeing anything pre-reveal would spoil the point.
    private var myAnswersRecap: [GameCompletionAnswerRecap] {
        store.rounds.compactMap { round in
            guard let response = store.myResponse(for: round, myID: myID),
                  case let .deepConversation(topic)? = store.content(for: round) else { return nil }
            return GameCompletionAnswerRecap(id: round.roundNumber, question: topic.topic, answer: response.answerValue)
        }
    }
}

#Preview {
    NavigationStack {
        DeepConversationsGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
