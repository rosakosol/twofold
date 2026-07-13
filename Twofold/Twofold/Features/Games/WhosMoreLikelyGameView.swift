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
                    gameType: .moreLikely, store: store, myID: myID, partnerID: partnerID,
                    myName: appModel.currentUser.name, partnerName: appModel.partner.name,
                    onPlayAnother: { dismiss() }
                )
            } else if let round = store.nextUnansweredRound(myID: myID), case let .moreLikely(prompt)? = store.content(for: round) {
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
        .navigationTitle(GameType.moreLikely.displayName)
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

    private func roundView(round: GameSessionRound, prompt: MoreLikelyPrompt) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Round \(round.roundNumber) of \(store.rounds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                        Text("Swipe or tap a side")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: Theme.Spacing.md) {
                        SwipeChoiceCard(
                            leftLabel: "🙋 ME",
                            leftColor: Theme.skyBlue,
                            rightLabel: "👉 \(appModel.partner.name.uppercased())",
                            rightColor: Theme.heartRed,
                            isDisabled: isSubmitting,
                            content: {
                                VStack(spacing: Theme.Spacing.lg) {
                                    Text(prompt.prompt)
                                        .font(.title3.weight(.bold))
                                        .multilineTextAlignment(.center)
                                    HStack(spacing: Theme.Spacing.xl) {
                                        VStack(spacing: Theme.Spacing.xs) {
                                            AvatarView(person: appModel.currentUser, size: 48, showsRing: true)
                                            Text("👈 Me").font(.caption.weight(.semibold)).foregroundStyle(Theme.skyBlue)
                                        }
                                        Image(systemName: "arrow.left.and.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                        VStack(spacing: Theme.Spacing.xs) {
                                            AvatarView(person: appModel.partner, size: 48, showsRing: true)
                                            Text("\(appModel.partner.name) 👉").font(.caption.weight(.semibold)).foregroundStyle(Theme.heartRed)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            },
                            onChooseLeft: { submit(round: round, value: myID.uuidString) },
                            onChooseRight: { submit(round: round, value: partnerID.uuidString) }
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
        await BackendService.notifyPartner(event: .gameReminder, detail: GameType.moreLikely.displayName, sessionID: sessionID, gameType: .moreLikely)
        isSendingReminder = false
    }
}

#Preview {
    NavigationStack {
        WhosMoreLikelyGameView(sessionID: UUID())
    }
    .environment(AppModel())
}
