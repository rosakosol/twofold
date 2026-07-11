//
//  TravelTriviaGameView.swift
//  Twofold
//
//  Competitive 5-question multiple choice quiz. Each answer is private until both partners
//  have answered the round (enforced by `game_responses` RLS, see the games migration) —
//  this view just walks round-by-round through whatever `GameSessionStore` reveals.
//

import SwiftUI

struct TravelTriviaGameView: View {
    let sessionID: UUID

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var displayedRoundNumber = 1
    @State private var isSubmitting = false

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
            } else if let round = store.rounds.first(where: { $0.roundNumber == displayedRoundNumber }),
                      case let .trivia(question)? = store.content(for: round) {
                roundView(round: round, question: question)
            } else {
                completionView
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
    }

    // MARK: - Round

    private func roundView(round: GameSessionRound, question: TriviaQuestion) -> some View {
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

                switch store.visibility(for: round, myID: myID) {
                case .needsAnswer:
                    answerOptions(round: round, question: question)
                case .waitingForPartner:
                    WaitingForPartnerView(partnerName: appModel.partner.name)
                case .revealed:
                    revealCard(round: round, question: question)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func answerOptions(round: GameSessionRound, question: TriviaQuestion) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    submit(round: round, value: option, isCorrect: option == question.correctAnswer)
                } label: {
                    Text(option)
                        .font(.subheadline.weight(.medium))
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

    private func revealCard(round: GameSessionRound, question: TriviaQuestion) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, myID: myID)
        return VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.sm) {
                answerRow(name: "You", value: mine?.answerValue, isCorrect: mine?.isCorrect, correctAnswer: question.correctAnswer)
                answerRow(name: appModel.partner.name, value: partner?.answerValue, isCorrect: partner?.isCorrect, correctAnswer: question.correctAnswer)
            }

            if let explanation = question.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }

            Button {
                displayedRoundNumber += 1
            } label: {
                Text(round.roundNumber >= store.rounds.count ? "See result" : "Next question")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func answerRow(name: String, value: String?, isCorrect: Bool?, correctAnswer: String) -> some View {
        HStack {
            Image(systemName: isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isCorrect == true ? Theme.leafGreen : Theme.heartRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                Text(value?.isEmpty == false ? value! : "Skipped").font(.subheadline.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Completion

    private var completionView: some View {
        let outcome = GameLogic.triviaOutcome(responses: store.responses, partnerAID: myID, partnerBID: partnerID)
        let myScore = GameLogic.triviaScore(responses: store.responses, responderID: myID)
        let partnerScore = GameLogic.triviaScore(responses: store.responses, responderID: partnerID)

        return VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.leafGreen)

            switch outcome {
            case .tie:
                Text("It's a tie!").font(.title2.weight(.bold))
            case .winner(let winnerID):
                Text(winnerID == myID ? "You won!" : "\(appModel.partner.name) won!")
                    .font(.title2.weight(.bold))
            }

            HStack(spacing: Theme.Spacing.xl) {
                StatTile(icon: "person.fill", value: "\(myScore)", label: "You", tint: Theme.skyBlue)
                StatTile(icon: "person.fill", value: "\(partnerScore)", label: appModel.partner.name, tint: Theme.heartRed)
            }

            Button {
                Task { await playAgain() }
            } label: {
                Text("Play again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(isSubmitting)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func submit(round: GameSessionRound, value: String, isCorrect: Bool) {
        isSubmitting = true
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value, isCorrect: isCorrect)
            isSubmitting = false
        }
    }

    private func playAgain() async {
        isSubmitting = true
        if let newSessionID = try? await BackendService.startGameSession(gameType: .travelTrivia) {
            displayedRoundNumber = 1
            await store.load(sessionID: newSessionID)
        }
        isSubmitting = false
    }
}

#Preview {
    NavigationStack {
        TravelTriviaGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
