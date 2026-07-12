//
//  GameCompletionView.swift
//  Twofold
//
//  Shown once I've answered every round but the session isn't fully completed yet (my partner
//  hasn't finished theirs). Shared across all 4 game types — nothing here is game-type-specific.
//

import SwiftUI

struct GameCompletionView: View {
    let partnerName: String
    let partnerProgress: PartnerProgress
    var isSendingReminder = false
    let onSendReminder: () -> Void
    let onPlayAnother: () -> Void

    @State private var showingReminderSentConfirmation = false

    private var progressStage: Int {
        switch partnerProgress {
        case .notStarted: 0
        case .inProgress: 1
        case .finished: 2
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

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

            Spacer()

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
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
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
}
