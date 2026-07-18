//
//  WhosMoreLikelyGameView.swift
//  Twofold
//
//  Playful prediction game — no winner/loser language, just a match count at the end. Each
//  partner answers all their own rounds independently; results reveal once both are done.
//

import SwiftUI

struct WhosMoreLikelyGameView: View {
    let sessionID: UUID
    /// Overrides the generic "Who's More Likely To" nav title — set to the deck's own title
    /// when reached via DeckEntryView, so the title doesn't shift once play actually starts.
    var title: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var hapticTrigger = false
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
                    gameType: .moreLikely, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }, title: title
                )
            } else if let round = store.displayedRound(myID: myID), case let .moreLikely(prompt)? = store.content(for: round) {
                roundView(round: round, prompt: prompt)
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
        .navigationTitle(title ?? GameType.moreLikely.displayName)
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
                        SupportMenuItems(userID: myID, context: "\(GameType.moreLikely.displayName) — session \(sessionID.uuidString)", showingNoMailAppAlert: $showingNoMailAppAlert)
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
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private func roundView(round: GameSessionRound, prompt: MoreLikelyPrompt) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        SwipeChoiceCard(
                            leftLabel: "🙋 \(appModel.currentUser.name.uppercased())",
                            rightLabel: "👉 \(appModel.partner.name.uppercased())",
                            isDisabled: isSubmitting,
                            content: {
                                VStack(spacing: Theme.Spacing.lg) {
                                    Text("\(round.roundNumber) / \(store.rounds.count)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer(minLength: Theme.Spacing.sm)

                                    // Centered vertically between the progress line and the
                                    // avatar row via the spacer on each side, rather than sitting
                                    // right under the progress line.
                                    Text(prompt.prompt)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)

                                    // Revisiting an already-answered round via the back button —
                                    // sits right under the question, rather than the previous
                                    // top-of-card pill placement, so it's clearly tied to what it
                                    // describes.
                                    if let previousAnswerLabel = previousAnswerLabel(for: round) {
                                        Text("You chose: \(previousAnswerLabel)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, Theme.Spacing.sm)
                                            .padding(.vertical, 6)
                                            .background(.white.opacity(0.22), in: Capsule())
                                    }

                                    Spacer(minLength: Theme.Spacing.sm)

                                    HStack(spacing: Theme.Spacing.xl) {
                                        VStack(spacing: Theme.Spacing.xs) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "chevron.left")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white.opacity(0.75))
                                                AvatarView(person: appModel.currentUser, size: 56, showsRing: true)
                                            }
                                            Text(appModel.currentUser.name)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                                .frame(maxWidth: 72)
                                        }
                                        VStack(spacing: Theme.Spacing.xs) {
                                            HStack(spacing: 4) {
                                                AvatarView(person: appModel.partner, size: 56, showsRing: true)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white.opacity(0.75))
                                            }
                                            Text(appModel.partner.name)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                                .frame(maxWidth: 72)
                                        }
                                    }
                                }
                            },
                            onChooseLeft: { submit(round: round, value: myID.uuidString) },
                            onChooseRight: { submit(round: round, value: partnerID.uuidString) }
                        )

                        Text("Swipe a side")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)

                        SkipButton(isDisabled: isSubmitting) {
                            submit(round: round, value: "")
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
        }
    }

    /// What to show in the card's "You chose: ___" pill when revisiting an already-answered
    /// round via the back button.
    private func previousAnswerLabel(for round: GameSessionRound) -> String? {
        guard let response = store.myResponse(for: round, myID: myID) else { return nil }
        switch response.answerValue {
        case "": return "Skipped"
        case myID.uuidString: return appModel.currentUser.name
        case partnerID.uuidString: return appModel.partner.name
        default: return nil
        }
    }

    private func submit(round: GameSessionRound, value: String) {
        hapticTrigger.toggle()
        isSubmitting = true
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value)
            isSubmitting = false
        }
    }

    private func sendReminder() async {
        isSendingReminder = true
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.moreLikely.displayName, sessionID: sessionID, gameType: .moreLikely)
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
}

#Preview {
    NavigationStack {
        WhosMoreLikelyGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
