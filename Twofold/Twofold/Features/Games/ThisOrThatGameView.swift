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

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var isSubmitting = false
    @State private var isSendingReminder = false
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
                    onPlayAnother: { dismiss() }
                )
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("This or That")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Leave", role: .destructive) {
                    Task { await store.abandon(); dismiss() }
                }
            }
        }
        .task { await store.load(sessionID: sessionID) }
        .task { await store.subscribeRealtime(sessionID: sessionID) }
        .onDisappear { store.stopRealtime() }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private func roundView(round: GameSessionRound, prompt: ThisOrThatPrompt) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Text("Round \(round.roundNumber) of \(store.rounds.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)

                    VStack(spacing: Theme.Spacing.sm) {
                        choiceButton(emoji: "🅰️", title: prompt.optionA, value: ThisOrThatChoice.optionA.rawValue, round: round)
                        Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                        choiceButton(emoji: "🅱️", title: prompt.optionB, value: ThisOrThatChoice.optionB.rawValue, round: round)
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

    private func choiceButton(emoji: String, title: String, value: String, round: GameSessionRound) -> some View {
        Button {
            submit(round: round, value: value)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(emoji).font(.title2)
                Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(Theme.ink)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(isSubmitting)
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
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.thisOrThat.displayName)
        isSendingReminder = false
    }
}

#Preview {
    NavigationStack {
        ThisOrThatGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
