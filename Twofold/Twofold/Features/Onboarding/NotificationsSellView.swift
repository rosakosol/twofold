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
    let emoji: String
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

    private var partnerImage: Image? {
        onboarding.partnerPhotoData
            .flatMap(UIImage.init(data:))
            .map(Image.init(uiImage:))
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
    // buildMessage (departed/airborne, arrival_time_change, landed) — the real pushes are
    // generic partner-to-partner text with no name, but onboarding's whole point is showing
    // what it'll feel like with the actual partner's name in it.
    private var previews: [NotificationPreview] {
        [
            NotificationPreview(
                emoji: "🛫",
                title: "Flight departed",
                body: "\(partnerName)'s flight has departed \(originLabel)."
            ),
            NotificationPreview(
                emoji: "🛬",
                title: "Arrival time updated",
                body: "\(partnerName)'s estimated arrival is in about an hour."
            ),
            NotificationPreview(
                emoji: "🎉",
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

    /// Matches the real iOS "communication notification" shape (large contact avatar + small
    /// app-icon badge overlaid at its corner, app name + relative timestamp in a small caption
    /// row above the title/body) — closer to what a real Twofold push actually looks like on a
    /// Lock Screen than the earlier oversized, badge-less card was.
    private func notificationBanner(
        _ preview: NotificationPreview
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {

            // MARK: Partner avatar + app-icon badge

            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if let partnerImage {
                        partnerImage
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(
                                Theme.skyBlue.opacity(0.20)
                            )

                        Text(preview.emoji)
                            .font(.system(size: 23))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.primaryButtonGradient)
                    Image("GlobeHeart")
                        .resizable()
                        .scaledToFit()
                        .padding(3.5)
                }
                .frame(width: 20, height: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white, lineWidth: 1.5)
                }
                .offset(x: 4, y: 4)
            }

            // MARK: Notification copy

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 4) {
                    Text("TWOFOLD")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                    Text("·")
                    Text("now")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.45))

                Text(preview.title)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.black.opacity(0.85)
                    )
                    .lineLimit(1)

                Text(preview.body)
                    .font(
                        .system(
                            size: 15,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(
                        Color.black.opacity(0.55)
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 88, alignment: .top)
        .background {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(Color.white.opacity(0.98))
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .strokeBorder(
                    Color.black.opacity(0.06),
                    lineWidth: 1
                )
            }
            .shadow(
                color: Color.black.opacity(0.28),
                radius: 18,
                x: 0,
                y: 10
            )
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
