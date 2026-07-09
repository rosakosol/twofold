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

struct NotificationsSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var isRequesting = false
    @State private var showCard1 = false
    @State private var showCard2 = false

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

    var body: some View {
        OnboardingScaffold(
            title: headline,
            subtitle: "Get flight updates when they matter, without constantly checking.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    notificationPreview(
                        emoji: "✈️",
                        title: "\(partnerName) is in the air",
                        body: "QF9 has departed Melbourne. We'll keep an eye on their journey"
                    )
                    .scaleEffect(showCard1 ? 1 : 0.8)
                    .opacity(showCard1 ? 1 : 0)
                    .offset(y: showCard1 ? 0 : -24)

                    notificationPreview(
                        emoji: "🛬",
                        title: "\(partnerName) has landed ❤️",
                        body: "QF9 has arrived in London."
                    )
                    .scaleEffect(showCard2 ? 1 : 0.8)
                    .opacity(showCard2 ? 1 : 0)
                    .offset(y: showCard2 ? 0 : -24)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.2)) {
                        showCard1 = true
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.7)) {
                        showCard2 = true
                    }
                }
            },
            primaryTitle: "Keep me updated",
            primaryAction: requestPermission,
            primaryDisabled: isRequesting
        )
        .sensoryFeedback(.impact(weight: .light), trigger: showCard1)
        .sensoryFeedback(.impact(weight: .light), trigger: showCard2)
    }

    private func notificationPreview(emoji: String, title: String, body: String) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(emoji)
                    .font(.title2)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(body).font(.caption).foregroundStyle(Theme.subtleInk)
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
