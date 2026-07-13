//
//  DiscussBeforeTravellingGameView.swift
//  Twofold
//
//  A guided conversation, not a competition — gentler copy/pacing than the other three games,
//  no scores or winners. Each partner writes a private initial response to every topic at their
//  own pace; once both are done, `GameResultsView` shows both sides side-by-side with
//  "Talked about" / "Come back later" marking for each topic.
//

import SwiftUI

struct DiscussBeforeTravellingGameView: View {
    let sessionID: UUID
    /// Overrides the generic "Deep Conversation" nav title — set to the deck's own title when
    /// reached via DeckEntryView, so the title doesn't shift once play actually starts.
    var title: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var responseText = ""
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
    @State private var isEditingAnswers = false

    private var myID: UUID { appModel.currentUser.id }
    private var partnerID: UUID { appModel.partner.id }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = store.errorMessage {
                GameErrorState(message: errorMessage)
            } else if let session = store.session, session.status == .abandoned {
                GameAbandonedState()
            } else if store.isRevealed {
                GameResultsView(
                    gameType: .discussBeforeTravelling, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
                )
            } else if let round = store.nextUnansweredRound(myID: myID), case let .discuss(topic)? = store.content(for: round) {
                roundView(round: round, topic: topic)
            } else {
                GameCompletionView(
                    partnerName: appModel.partner.name,
                    partnerProgress: store.partnerProgress(partnerID: partnerID),
                    isSendingReminder: isSendingReminder,
                    onSendReminder: { Task { await sendReminder() } },
                    onPlayAnother: { dismiss() },
                    myAnswersRecap: myAnswersRecap,
                    isEditingAnswers: isEditingAnswers,
                    onEditAnswers: { Task { await editAnswers() } },
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
        .navigationTitle(title ?? GameType.discussBeforeTravelling.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Not offered once results are showing — abandoning a completed session would mark
            // it "abandoned" and drop it out of deck progress/history, which makes no sense for
            // a game that's already finished.
            if !store.isRevealed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leave", role: .destructive) {
                        Task { await store.abandon(); dismiss() }
                    }
                }
            }
        }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
            if isConnected, !wasConnected { Task { await store.syncPendingResponses() } }
        }
    }

    private func roundView(round: GameSessionRound, topic: DiscussionTopic) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Topic \(round.roundNumber) of \(store.rounds.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text(topic.topic)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                responseInput(round: round)
            }
            .padding(Theme.Spacing.lg)
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
                Text("Share")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(isSubmitting)

            SkipButton(isDisabled: isSubmitting) {
                submit(round: round, value: "")
            }
        }
    }

    private func submit(round: GameSessionRound, value: String) {
        isSubmitting = true
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value)
            responseText = ""
            isSubmitting = false
        }
    }

    private func sendReminder() async {
        isSendingReminder = true
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.discussBeforeTravelling.displayName, sessionID: sessionID, gameType: .discussBeforeTravelling)
        isSendingReminder = false
    }

    private func editAnswers() async {
        isEditingAnswers = true
        await store.editMyAnswers()
        isEditingAnswers = false
    }

    /// My own private responses so far — safe to show to me alone even before the session
    /// reveals, unlike the other games where seeing anything pre-reveal would spoil the point.
    private var myAnswersRecap: [GameCompletionAnswerRecap] {
        store.rounds.compactMap { round in
            guard let response = store.myResponse(for: round, myID: myID),
                  case let .discuss(topic)? = store.content(for: round) else { return nil }
            return GameCompletionAnswerRecap(id: round.roundNumber, question: topic.topic, answer: response.answerValue)
        }
    }
}

#Preview {
    NavigationStack {
        DiscussBeforeTravellingGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
