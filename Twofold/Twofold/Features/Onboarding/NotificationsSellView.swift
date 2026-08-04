//
//  NotificationsSellView.swift
//  Twofold
//
//  Sells the benefit before ever showing the system prompt. The native permission dialog
//  only appears once the user taps "Keep me updated" — if they deny it, onboarding just
//  continues normally and Twofold never asks again.
//
//  Styled around an oversized Lock Screen mockup with notifications floating above the
//  phone chassis, closely matching the visual language of a real iOS Lock Screen.
//

import Combine
import SwiftUI
import UIKit
import UserNotifications

private struct NotificationPreview {
    let title: String
    let body: String
}

struct NotificationsSellView: View {
    @Environment(OnboardingModel.self) private var onboarding

    @State private var isRequesting = false
    @State private var shownCards: Set<Int> = []
    @State private var now = Date()

    private let clock = Timer
        .publish(every: 30, on: .main, in: .common)
        .autoconnect()

    private var partnerName: String {
        onboarding.partnerName
    }

    private var originLabel: String {
        guard let city = onboarding.illustrativeOriginCity else {
            return "\(onboarding.partnerPossessive) city"
        }

        if let iata = city.iataCode {
            return "\(city.city) (\(iata))"
        }

        return city.city
    }

    private var destinationLabel: String {
        onboarding.homeCity?.displayCity ?? "your city"
    }

    private var headline: String {
        switch onboarding.situation {
        case .liveTogetherTravelOften:
            "Know when \(partnerName) is on \(onboarding.partnerPossessive) way home."
        default:
            "Always know when \(partnerName) has landed"
        }
    }

    // Mirrors the real push-notification vocabulary from supabase/functions/_shared/notify.ts's
    // buildMessage (departed/airborne, landed) and notifyArrivalReminder (the fixed 1h/30m-before-
    // arrival reminders) — the real pushes are generic partner-to-partner text with no name, but
    // onboarding's whole point is showing what it'll feel like with the actual partner's name in it.
    private var previews: [NotificationPreview] {
        [
            NotificationPreview(
                title: "Flight departed",
                body: "\(partnerName)'s flight has departed \(originLabel)."
            ),
            NotificationPreview(
                title: "Landing in 1 hour",
                body: "\(partnerName)'s flight is expected to land in about 1 hour."
            ),
            NotificationPreview(
                title: "Flight landed",
                body: "\(partnerName)'s flight has landed in \(destinationLabel) ❤️"
            ),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            title: headline,
            subtitle: "Get flight updates when they matter.",
            content: {
                phoneMock
                    .onAppear {
                        animateNotifications()
                    }
            },
            primaryTitle: "Keep me updated",
            primaryAction: requestPermission,
            primaryDisabled: isRequesting
        )
        .sensoryFeedback(
            .impact(weight: .light),
            trigger: shownCards
        )
        .onReceive(clock) {
            now = $0
        }
    }

    // MARK: - Phone Mock

    private var phoneMock: some View {
        LockScreenPhoneMock(now: now) {
            // -72 (was -58) — pulls the stack tighter, so each card steps down by a smaller
            // visible amount from the one before it.
            VStack(spacing: -72) {
                ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                    notificationBanner(preview)
                        .zIndex(Double(index))
                        .scaleEffect(shownCards.contains(index) ? 1 : 0.88, anchor: .top)
                        .opacity(shownCards.contains(index) ? 1 : 0)
                        .offset(y: shownCards.contains(index) ? 0 : -30)
                }
            }
            .padding(.top, 245)
        }
    }

    // MARK: - Notification Banner

    /// Measured pixel-for-pixel off an actual `xcrun simctl push` capture on the Lock Screen:
    /// square app-icon badge (real Twofold pushes are plain `aps.alert` payloads with no
    /// attached avatar, so there's no contact photo — this isn't a communication notification),
    /// title and relative timestamp sharing one row, body directly beneath at the same near-
    /// white brightness as the title, and no separate app-name caption line. The dark frosted
    /// card, icon size/position, and type sizes all match that capture.
    private func notificationBanner(
        _ preview: NotificationPreview
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {

            // MARK: App icon

            ZStack {
                Theme.backgroundGradient
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // MARK: Notification copy

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(preview.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("now")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(preview.body)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
                .background {
                    // The stacked preview cards overlap (see VStack spacing below) — a pure
                    // ultraThinMaterial lets the card behind show through and read as clutter,
                    // so an opaque scrim sits under the material to keep each card legible.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
        }
        // 10 (was 28) — same "pop out" margin the Live Activity card uses, so the banner
        // stretches wider than the phone chassis instead of sitting flush inside it.
        .padding(.horizontal, 10)
    }

    // MARK: - Animation

    private func animateNotifications() {
        shownCards.removeAll()

        for index in previews.indices {
            withAnimation(
                .spring(
                    response: 0.5,
                    dampingFraction: 0.68
                )
                .delay(
                    0.3 + Double(index) * 0.5
                )
            ) {
                _ = shownCards.insert(index)
            }
        }
    }

    // MARK: - Notification Permission

    private func requestPermission() {
        isRequesting = true

        Task {
            let granted = (
                try? await UNUserNotificationCenter
                    .current()
                    .requestAuthorization(
                        options: [
                            .alert,
                            .sound,
                            .badge,
                        ]
                    )
            ) ?? false

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
