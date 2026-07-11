//
//  DiscussBeforeTravellingGameView.swift
//  Twofold
//
//  A guided conversation, not a competition — gentler copy/pacing than the other three games,
//  no scores or winners. Each partner writes a private initial response, then a shared
//  discussion screen lets the couple mark the topic "Talked about" or "Come back later".
//

import SwiftUI

struct DiscussBeforeTravellingGameView: View {
    let sessionID: UUID

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = GameSessionStore()
    @State private var displayedRoundNumber = 1
    @State private var responseText = ""
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
                      case let .discuss(topic)? = store.content(for: round) {
                roundView(round: round, topic: topic)
            } else {
                completionView
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Discuss Before Travelling")
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

                switch store.visibility(for: round, myID: myID) {
                case .needsAnswer:
                    responseInput(round: round)
                case .waitingForPartner:
                    VStack(spacing: Theme.Spacing.sm) {
                        WaitingForPartnerView(partnerName: appModel.partner.name)
                        Text("Take your time — there's no rush with this one.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                case .revealed:
                    discussionCard(round: round)
                }
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

    private func discussionCard(round: GameSessionRound) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, myID: myID)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            responseBlock(name: "You", text: mine?.answerValue)
            Divider()
            responseBlock(name: appModel.partner.name, text: partner?.answerValue)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    mark(round: round, status: .comeBackLater)
                } label: {
                    Text("Come back later")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(Theme.ink)
                        .background(Theme.cardBackground, in: Capsule())
                }
                Button {
                    mark(round: round, status: .talkedAbout)
                } label: {
                    Text("Talked about")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(Theme.leafGreen, in: Capsule())
                }
            }
            .disabled(isSubmitting)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func responseBlock(name: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionView: some View {
        let talkedAbout = store.rounds.filter { $0.discussionStatus == .talkedAbout }.count
        let comeBackLater = store.rounds.filter { $0.discussionStatus == .comeBackLater }.count

        return VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.leafGreen)

            Text("Nice conversation")
                .font(.title2.weight(.bold))

            Text(comeBackLater > 0
                ? "You talked about \(talkedAbout) of \(store.rounds.count) topics, with \(comeBackLater) to revisit later."
                : "You talked through all \(store.rounds.count) topics.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)

            Button {
                Task { await playAgain() }
            } label: {
                Text("Start a new conversation")
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
            responseText = ""
            isSubmitting = false
        }
    }

    private func mark(round: GameSessionRound, status: DiscussionRoundStatus) {
        isSubmitting = true
        Task {
            await store.markDiscussionRound(round, status: status)
            displayedRoundNumber += 1
            isSubmitting = false
        }
    }

    private func playAgain() async {
        isSubmitting = true
        if let newSessionID = try? await BackendService.startGameSession(gameType: .discussBeforeTravelling) {
            displayedRoundNumber = 1
            await store.load(sessionID: newSessionID)
        }
        isSubmitting = false
    }
}

#Preview {
    NavigationStack {
        DiscussBeforeTravellingGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
