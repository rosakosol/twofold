//
//  WhosMoreLikelyGameView.swift
//  Twofold
//
//  Playful prediction game — no winner/loser language, just a match count at the end.
//

import SwiftUI

struct WhosMoreLikelyGameView: View {
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
                      case let .moreLikely(prompt)? = store.content(for: round) {
                roundView(round: round, prompt: prompt)
            } else {
                completionView
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Who's More Likely To")
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

    private func roundView(round: GameSessionRound, prompt: MoreLikelyPrompt) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Round \(round.roundNumber) of \(store.rounds.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text(prompt.prompt)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                switch store.visibility(for: round, myID: myID) {
                case .needsAnswer:
                    VStack(spacing: Theme.Spacing.sm) {
                        choiceButton(title: "Me", personID: myID, round: round)
                        choiceButton(title: appModel.partner.name, personID: partnerID, round: round)
                        SkipButton(isDisabled: isSubmitting) {
                            submit(round: round, value: "")
                        }
                    }
                case .waitingForPartner:
                    WaitingForPartnerView(partnerName: appModel.partner.name)
                case .revealed:
                    revealCard(round: round)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func choiceButton(title: String, personID: UUID, round: GameSessionRound) -> some View {
        Button {
            submit(round: round, value: personID.uuidString)
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(Theme.ink)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(isSubmitting)
    }

    private func revealCard(round: GameSessionRound) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, myID: myID)
        let matched = mine?.answerValue == partner?.answerValue && mine?.answerValue.isEmpty == false

        return VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.sm) {
                choiceReveal(name: "You", answerValue: mine?.answerValue)
                choiceReveal(name: appModel.partner.name, answerValue: partner?.answerValue)
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

    private func choiceReveal(name: String, answerValue: String?) -> some View {
        HStack {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Spacer()
            Text(personName(for: answerValue)).font(.subheadline.weight(.medium))
        }
    }

    private func personName(for answerValue: String?) -> String {
        guard let answerValue, !answerValue.isEmpty else { return "Skipped" }
        if answerValue == myID.uuidString { return "You" }
        if answerValue == partnerID.uuidString { return appModel.partner.name }
        return "—"
    }

    private var completionView: some View {
        let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
        return VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.heartRed)

            Text("You matched on \(matches) out of \(store.rounds.count)")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

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
        if let newSessionID = try? await BackendService.startGameSession(gameType: .moreLikely) {
            displayedRoundNumber = 1
            await store.load(sessionID: newSessionID)
        }
        isSubmitting = false
    }
}

#Preview {
    NavigationStack {
        WhosMoreLikelyGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
