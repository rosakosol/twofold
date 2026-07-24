//
//  ThisOrThatGameView.swift
//  Twofold
//
//  Quick preference/compatibility game — two options per round. Each partner answers all their
//  own rounds independently; match count + percentage reveal once both are done.
//

import PostHog
import SwiftUI

struct ThisOrThatGameView: View {
    let sessionID: UUID
    /// Overrides the generic "This or That" nav title — set to the deck's own title when
    /// reached via DeckEntryView, so the title doesn't shift once play actually starts.
    var title: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var hapticTrigger = false
    @State private var showingReportSheet = false
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
                    gameType: .thisOrThat, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }, title: title
                )
            } else if let round = store.displayedRound(myID: myID), case let .thisOrThat(prompt)? = store.content(for: round) {
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
        .navigationTitle(title ?? GameType.thisOrThat.displayName)
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
            store.gameIssueContext(gameType: .thisOrThat, deckTitle: title, myID: myID)
        }
        .gameLeaveConfirmation(isPresented: $showingLeaveConfirm) { Task { await leaveGame() } }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
            if isConnected, !wasConnected { Task { await store.syncPendingResponses() } }
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .postHogScreenView("Games: This or That")
    }

    private func roundView(round: GameSessionRound, prompt: ThisOrThatPrompt) -> some View {
        // Plain VStack, not a ScrollView — SwipeChoiceCard's DragGesture tracks the full
        // translation (not axis-locked to horizontal, since the card visibly follows a diagonal
        // drag too), so a ScrollView here competed with it over the same touch, exactly the two-
        // recognizers problem SwipeChoiceCard's own header comment describes having fixed once
        // already (there, for tap vs. swipe). `minHeight: geometry.size.height` still centers
        // this content vertically without installing a scroll gesture.
        GeometryReader { geometry in
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    SwipeChoiceCard(
                        leftLabel: "🅰️ THIS",
                        rightLabel: "🅱️ THAT",
                        isDisabled: isSubmitting,
                        content: {
                            VStack(spacing: Theme.Spacing.lg) {
                                Text("\(round.roundNumber) / \(store.rounds.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: Theme.Spacing.md)

                                // One flowing "Answer or Answer" phrase, not separate stacked
                                // lines — built as a single AttributedString/Text rather than
                                // the `Text + Text` concatenation this replaced, which iOS 26
                                // deprecated in favor of exactly this. Constrained to one
                                // line — shrinking to fit rather than wrapping keeps the card
                                // height consistent regardless of how long either option is.
                                optionsPhrase(prompt)
                                    .font(.title2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.4)
                                    .frame(maxWidth: .infinity)

                                // Revisiting an already-answered round via the back button —
                                // sits right under the question, rather than the previous
                                // top-of-card pill placement, so it's clearly tied to what it
                                // describes.
                                if let previousAnswerLabel = previousAnswerLabel(for: round, prompt: prompt) {
                                    Text("You chose: \(previousAnswerLabel)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, 6)
                                        .background(.white.opacity(0.22), in: Capsule())
                                }

                                Spacer(minLength: Theme.Spacing.md)
                            }
                        },
                        onChooseLeft: { submit(round: round, value: ThisOrThatChoice.optionA.rawValue) },
                        onChooseRight: { submit(round: round, value: ThisOrThatChoice.optionB.rawValue) }
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

    /// Both options now read in plain white (the card itself is the sky-blue-to-leaf-green
    /// gradient, see `SwipeChoiceCard`) rather than tinting each option its own swipe-direction
    /// color — colored text didn't hold up for contrast against the new gradient background.
    private func optionsPhrase(_ prompt: ThisOrThatPrompt) -> Text {
        var optionA = AttributedString(prompt.optionA)
        optionA.foregroundColor = .white
        optionA.font = .title2.weight(.heavy)

        var or = AttributedString(" or ")
        or.foregroundColor = .white.opacity(0.75)
        var phrase = optionA
        phrase += or

        var optionB = AttributedString(prompt.optionB)
        optionB.foregroundColor = .white
        optionB.font = .title2.weight(.heavy)
        phrase += optionB

        return Text(phrase)
    }

    /// What to show in the card's "You chose: ___" pill when revisiting an already-answered
    /// round via the back button — nil for a fresh round (no response yet), so the pill simply
    /// doesn't appear.
    private func previousAnswerLabel(for round: GameSessionRound, prompt: ThisOrThatPrompt) -> String? {
        guard let response = store.myResponse(for: round, myID: myID) else { return nil }
        if response.answerValue.isEmpty { return "Skipped" }
        switch response.answerValue {
        case ThisOrThatChoice.optionA.rawValue: return prompt.optionA
        case ThisOrThatChoice.optionB.rawValue: return prompt.optionB
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
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.thisOrThat.displayName, sessionID: sessionID, gameType: .thisOrThat)
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
        ThisOrThatGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
