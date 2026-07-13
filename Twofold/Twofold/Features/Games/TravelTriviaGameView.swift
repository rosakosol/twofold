//
//  TravelTriviaGameView.swift
//  Twofold
//
//  Competitive 5-question multiple choice quiz. Each partner answers all their own rounds
//  independently, at their own pace — results (including who got what right) only reveal once
//  both partners have answered every round (see `GameSessionStore.isRevealed`).
//

import SwiftUI

struct TravelTriviaGameView: View {
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
                    gameType: .travelTrivia, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
                )
            } else if let round = store.nextUnansweredRound(myID: myID), case let .trivia(question)? = store.content(for: round) {
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
                    onPlayAnother: { dismiss() }
                )
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Travel Trivia Battle")
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

    // MARK: - Round

    private static let optionEmoji = ["1️⃣", "2️⃣", "3️⃣", "4️⃣"]

    private func roundView(round: GameSessionRound, question: TriviaQuestion) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Question \(round.roundNumber) of \(store.rounds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                        Text(question.category.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.skyBlue)
                        Text(question.question)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
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
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                Button {
                    submit(round: round, value: option, isCorrect: option == question.correctAnswer)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(Self.optionEmoji[index % Self.optionEmoji.count]).font(.title3)
                        Text(option).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(Theme.ink)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .disabled(isSubmitting)
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
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.travelTrivia.displayName)
        isSendingReminder = false
    }
}

#Preview {
    NavigationStack {
        TravelTriviaGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
