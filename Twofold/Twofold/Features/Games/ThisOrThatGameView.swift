//
//  ThisOrThatGameView.swift
//  Twofold
//
//  Quick preference/compatibility game — two options per round, match count + percentage at
//  the end. Non-judgmental, easy to skip.
//

import SwiftUI

struct ThisOrThatGameView: View {
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
                      case let .thisOrThat(prompt)? = store.content(for: round) {
                roundView(round: round, prompt: prompt)
            } else {
                completionView
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
    }

    private func roundView(round: GameSessionRound, prompt: ThisOrThatPrompt) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Round \(round.roundNumber) of \(store.rounds.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)

                switch store.visibility(for: round, myID: myID) {
                case .needsAnswer:
                    VStack(spacing: Theme.Spacing.sm) {
                        choiceButton(title: prompt.optionA, value: ThisOrThatChoice.optionA.rawValue, round: round)
                        Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                        choiceButton(title: prompt.optionB, value: ThisOrThatChoice.optionB.rawValue, round: round)
                        SkipButton(isDisabled: isSubmitting) {
                            submit(round: round, value: "")
                        }
                    }
                case .waitingForPartner:
                    WaitingForPartnerView(partnerName: appModel.partner.name)
                case .revealed:
                    revealCard(round: round, prompt: prompt)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func choiceButton(title: String, value: String, round: GameSessionRound) -> some View {
        Button {
            submit(round: round, value: value)
        } label: {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(Theme.ink)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(isSubmitting)
    }

    private func revealCard(round: GameSessionRound, prompt: ThisOrThatPrompt) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, myID: myID)
        let matched = mine?.answerValue == partner?.answerValue && mine?.answerValue.isEmpty == false

        return VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.sm) {
                choiceReveal(name: "You", answerValue: mine?.answerValue, prompt: prompt)
                choiceReveal(name: appModel.partner.name, answerValue: partner?.answerValue, prompt: prompt)
            }

            if matched {
                Label("You matched!", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.heartRed)
            }

            Button {
                displayedRoundNumber += 1
            } label: {
                Text(round.roundNumber >= store.rounds.count ? "See result" : "Next round")
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

    private func choiceReveal(name: String, answerValue: String?, prompt: ThisOrThatPrompt) -> some View {
        HStack {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Spacer()
            Text(optionLabel(for: answerValue, prompt: prompt)).font(.subheadline.weight(.medium))
        }
    }

    private func optionLabel(for answerValue: String?, prompt: ThisOrThatPrompt) -> String {
        switch answerValue {
        case ThisOrThatChoice.optionA.rawValue: prompt.optionA
        case ThisOrThatChoice.optionB.rawValue: prompt.optionB
        default: "Skipped"
        }
    }

    private var completionView: some View {
        let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
        let percentage = GameLogic.matchPercentage(matches: matches, totalRounds: store.rounds.count)
        return VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("\(matches) of \(store.rounds.count) matched")
                .font(.title2.weight(.bold))
            Text("\(percentage)% compatibility")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)

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

    private func submit(round: GameSessionRound, value: String) {
        isSubmitting = true
        Task {
            await store.submit(roundNumber: round.roundNumber, answerValue: value)
            isSubmitting = false
        }
    }

    private func playAgain() async {
        isSubmitting = true
        if let newSessionID = try? await BackendService.startGameSession(gameType: .thisOrThat) {
            displayedRoundNumber = 1
            await store.load(sessionID: newSessionID)
        }
        isSubmitting = false
    }
}

#Preview {
    NavigationStack {
        ThisOrThatGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
