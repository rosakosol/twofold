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

    // CoupleLocationsView requires both cities before you can advance, so these are always
    // real by the time this screen runs too. `illustrativeOriginCity` is normally the
    // partner's city, but swaps in a random other one if the couple lives in the same city
    // (matching what the Live Activity sell screen shows, since both read from the same
    // cached value on `onboarding`) — otherwise this example flight would depart and arrive
    // in the same place.
    private var originLabel: String {
        guard let city = onboarding.illustrativeOriginCity else { return "\(onboarding.partnerPossessive) city" }
        if let iata = city.iataCode { return "\(city.city) (\(iata))" }
        return city.city
    }

    private var destinationLabel: String {
        onboarding.homeCity?.city ?? "your city"
    }

    private var headline: String {
        switch onboarding.situation {
        case .liveTogetherTravelOften:
            "Know when \(partnerName) is on \(onboarding.partnerPossessive) way home."
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
                body: "QF9 departed \(originLabel)."
            ),
            NotificationPreview(
                emoji: "✈️",
                title: "\(partnerName) is in the air",
                body: "QF9 has departed \(originLabel). We'll keep an eye on \(onboarding.partnerPossessive) journey"
            ),
            NotificationPreview(
                emoji: "🛬",
                title: "\(partnerName) is landing soon",
                body: "Touch down is in an hour."
            ),
            NotificationPreview(
                emoji: "🎉",
                title: "\(partnerName) has landed ❤️",
                body: "QF9 has arrived in \(destinationLabel)."
            ),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
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
