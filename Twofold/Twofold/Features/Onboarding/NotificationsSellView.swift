//
//  NotificationsSellView.swift
//  Twofold
//
//  Sells the benefit before ever showing the system prompt. The native permission dialog
//  only appears once the user taps "Keep me updated" — if they deny it, onboarding just
//  continues normally and Twofold never asks again.
//

import SwiftUI
import UserNotifications

private struct NotificationPreview {
    let emoji: String
    let title: String
    let body: String
}

struct NotificationsSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var isRequesting = false
    @State private var shownCards: Set<Int> = []

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var headline: String {
        switch onboarding.situation {
        case .liveTogetherTravelOften:
            "Know when \(partnerName) is on their way home."
        default:
            "Never wonder if \(partnerName) has landed."
        }
    }

    /// Mirrors the same journey moments shown on the Live Activity sell screen, so the two
    /// permission-selling screens feel like one connected pitch.
    private var previews: [NotificationPreview] {
        [
            NotificationPreview(
                emoji: "🛫",
                title: "\(partnerName) has departed",
                body: "QF9 departed Melbourne (MEL)."
            ),
            NotificationPreview(
                emoji: "✈️",
                title: "\(partnerName) is in the air",
                body: "QF9 has departed Melbourne. We'll keep an eye on their journey"
            ),
            NotificationPreview(
                emoji: "🛬",
                title: "\(partnerName) is landing soon",
                body: "Touch down is in an hour."
            ),
            NotificationPreview(
                emoji: "🎉",
                title: "\(partnerName) has landed ❤️",
                body: "QF9 has arrived in London."
            ),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            title: headline,
            subtitle: "Get flight updates when they matter, without constantly checking.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                        notificationPreview(preview)
                            .scaleEffect(shownCards.contains(index) ? 1 : 0.8)
                            .opacity(shownCards.contains(index) ? 1 : 0)
                            .offset(y: shownCards.contains(index) ? 0 : -24)
                    }
                }
                .onAppear {
                    for index in previews.indices {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.2 + Double(index) * 0.35)) {
                            shownCards.insert(index)
                        }
                    }
                }
            },
            primaryTitle: "Keep me updated",
            primaryAction: requestPermission,
            primaryDisabled: isRequesting
        )
        .sensoryFeedback(.impact(weight: .light), trigger: shownCards)
    }

    private func notificationPreview(_ preview: NotificationPreview) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(preview.emoji)
                    .font(.title2)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title).font(.subheadline.weight(.semibold))
                    Text(preview.body).font(.caption).foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            onboarding.notificationsGranted = granted
            isRequesting = false
            onboarding.path.append(.liveActivitySell)
        }
    }
}

#Preview {
    NavigationStack {
        NotificationsSellView()
    }
    .environment(OnboardingModel())
}
