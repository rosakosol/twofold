//
//  GameCompletionView.swift
//  Twofold
//
//  Shown once I've answered every round but the session isn't fully completed yet (my partner
//  hasn't finished theirs). Shared across all 4 game types — nothing here is game-type-specific,
//  except `myAnswersRecap` (only Deep Conversations passes one — my own responses are
//  always visible to me regardless of session completion, unlike the match/trivia games where
//  showing anything pre-reveal would spoil the point).
//

import PostHog
import SwiftUI

struct GameCompletionAnswerRecap: Identifiable {
    let id: Int
    let question: String
    let answer: String
}

struct GameCompletionView: View {
    let partnerName: String
    let partnerProgress: PartnerProgress
    var isSendingReminder = false
    let onSendReminder: () -> Void
    let onPlayAnother: () -> Void
    var myAnswersRecap: [GameCompletionAnswerRecap] = []
    var onEditAnswers: (() -> Void)? = nil
    /// Answers still sitting in `GameSessionStore`'s offline queue for this session — shown as
    /// its own reassurance card since "waiting for partner" alone would be misleading here (my
    /// own answers haven't even reached the server yet, regardless of what my partner's doing).
    var pendingSyncCount = 0

    @Environment(AppModel.self) private var appModel
    @State private var showingReminderSentConfirmation = false

    private var progressStage: Int {
        switch partnerProgress {
        case .notStarted: 0
        case .inProgress: 1
        case .finished: 2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Text("🎉").font(.system(size: 56))

                    VStack(spacing: Theme.Spacing.sm) {
                        Text("You're finished!")
                            .font(.title2.weight(.bold))
                        Text("Now it's \(partnerName)'s turn. We've sent them an invitation. Results unlock once you've both completed the game.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    if pendingSyncCount > 0 {
                        offlineSyncCard
                    }

                    VStack(spacing: Theme.Spacing.md) {
                        Text("Waiting for \(partnerName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                        HStack(spacing: Theme.Spacing.lg) {
                            stepDot(title: "Started", filled: progressStage >= 1)
                            stepDot(title: "In Progress", filled: progressStage >= 1)
                            stepDot(title: "Finished", filled: progressStage >= 2)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    if !myAnswersRecap.isEmpty {
                        recapSection
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onSendReminder) {
                    HStack {
                        if isSendingReminder {
                            ProgressView()
                        } else {
                            Text("Send Reminder")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(Theme.ink)
                    .background(Theme.cardBackground, in: Capsule())
                }
                .disabled(isSendingReminder)

                Button(action: onPlayAnother) {
                    Text("Play Another Game")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)

                if let onEditAnswers {
                    Button(action: onEditAnswers) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Edit My Answers")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .onAppear {
            // `AppModel.gameDecks`/`deckProgress` are cached for the whole app session and only
            // ever refreshed explicitly — without this, the deck list's "you're done" checkmark
            // for my own side stayed stale until the app relaunched, even though I've just
            // finished every round of the session backing this exact screen.
            Task { await appModel.refreshGameDecks() }
        }
        // `isSendingReminder` is owned by the caller (each typed game view runs its own
        // fire-and-forget `notifyPartner` call) — watching its true → false transition here
        // means every call site gets this confirmation for free, no changes needed there.
        .onChange(of: isSendingReminder) { wasSending, isSending in
            if wasSending, !isSending {
                showingReminderSentConfirmation = true
            }
        }
        .alert("Reminder Sent", isPresented: $showingReminderSentConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Notification sent to \(partnerName).")
        }
        .postHogScreenView("Games: Completion")
    }

    private var offlineSyncCard: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(Theme.subtleInk)
            Text("Saved for later")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("You're offline. Your \(pendingSyncCount == 1 ? "answer is" : "answers are") saved on this device and will send automatically once you're back online.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("What you shared")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(myAnswersRecap) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.question)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text(entry.answer.isEmpty ? "Skipped this one" : entry.answer)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.sm)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private func stepDot(title: String, filled: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(filled ? Theme.skyBlue : Theme.subtleInk.opacity(0.25))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption2)
                .foregroundStyle(filled ? Theme.ink : Theme.subtleInk)
        }
    }
}

#Preview {
    GameCompletionView(partnerName: "Erin", partnerProgress: .inProgress(answered: 2, total: 5), onSendReminder: {}, onPlayAnother: {})
        .environment(AppModel())
}

#Preview("Offline") {
    GameCompletionView(partnerName: "Erin", partnerProgress: .notStarted, onSendReminder: {}, onPlayAnother: {}, pendingSyncCount: 3)
        .environment(AppModel())
}

#Preview("With recap") {
    GameCompletionView(
        partnerName: "Erin", partnerProgress: .notStarted, onSendReminder: {}, onPlayAnother: {},
        myAnswersRecap: [
            GameCompletionAnswerRecap(id: 1, question: "What's one thing you're excited about for this trip?", answer: "Trying all the street food."),
            GameCompletionAnswerRecap(id: 2, question: "Any travel fears to talk through?", answer: ""),
        ],
        onEditAnswers: {}
    )
    .environment(AppModel())
}
