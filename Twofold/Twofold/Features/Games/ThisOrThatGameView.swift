//
//  ThisOrThatGameView.swift
//  Twofold
//
//  Quick preference/compatibility game — two options per round. Each partner answers all their
//  own rounds independently; match count + percentage reveal once both are done.
//

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
    @State private var isEditingAnswers = false
    @State private var hapticTrigger = false

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
                    gameType: .thisOrThat, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
                )
            } else if let round = store.nextUnansweredRound(myID: myID), case let .thisOrThat(prompt)? = store.content(for: round) {
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
        // Pinned against the round-transition spring below via `.transaction { $0.animation = nil }`
        // — without it, the full-bleed background was observed interpolating its own width
        // alongside that animation instead of staying static.
        .background(Theme.backgroundGradient.ignoresSafeArea().transaction { $0.animation = nil })
        .navigationTitle(title ?? GameType.thisOrThat.displayName)
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
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private func roundView(round: GameSessionRound, prompt: ThisOrThatPrompt) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Text("Round \(round.roundNumber) of \(store.rounds.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)

                    Text("Swipe or tap a side")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)

                    VStack(spacing: Theme.Spacing.md) {
                        SwipeChoiceCard(
                            leftLabel: "🅰️ THIS",
                            leftColor: Theme.skyBlue,
                            rightLabel: "🅱️ THAT",
                            rightColor: Theme.heartRed,
                            isDisabled: isSubmitting,
                            content: {
                                // Concatenated Text (not separate stacked lines) so "Answer or
                                // Answer" reads and wraps as one flowing phrase, with each
                                // option keeping its own swipe-direction color.
                                (
                                    Text("👈 ")
                                    + Text(prompt.optionA).foregroundStyle(Theme.skyBlue).fontWeight(.heavy)
                                    + Text(" or ").foregroundStyle(Theme.subtleInk)
                                    + Text(prompt.optionB).foregroundStyle(Theme.heartRed).fontWeight(.heavy)
                                    + Text(" 👉")
                                )
                                .font(.title2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            },
                            onChooseLeft: { submit(round: round, value: ThisOrThatChoice.optionA.rawValue) },
                            onChooseRight: { submit(round: round, value: ThisOrThatChoice.optionB.rawValue) }
                        )

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

    private func editAnswers() async {
        isEditingAnswers = true
        await store.editMyAnswers()
        isEditingAnswers = false
    }
}

#Preview {
    NavigationStack {
        ThisOrThatGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
