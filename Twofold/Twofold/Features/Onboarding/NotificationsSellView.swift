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

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

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
        onboarding.homeCity?.city ?? "your city"
    }

    private var headline: String {
        switch onboarding.situation {
        case .liveTogetherTravelOften:
            "Know when \(partnerName) is on \(onboarding.partnerPossessive) way home."
        default:
            "Always know when \(partnerName) has landed"
        }
    }

    private var previews: [NotificationPreview] {
        [
            NotificationPreview(
                emoji: "🛫",
                title: "\(partnerName) has departed",
                body: "QF9 departed \(originLabel)."
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
        GeometryReader { geometry in
            let safeWidth = geometry.size.width.isFinite
                ? geometry.size.width
                : 340

            let phoneWidth = min(
                max(safeWidth - 60, 280),
                390
            )

            ZStack(alignment: .top) {

                // MARK: Phone chassis

                RoundedRectangle(
                    cornerRadius: 62,
                    style: .continuous
                )
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 62,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.white.opacity(0.17),
                        lineWidth: 12
                    )
                }
                .frame(
                    width: phoneWidth,
                    height: 760
                )
                .zIndex(0)

                // MARK: Lock Screen UI

                VStack(spacing: 0) {

                    // Dynamic Island
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(
                            width: 82,
                            height: 24
                        )
                        .padding(.top, 32)

                    // Lock Screen clock
                    Text(
                        Self.clockFormatter.string(from: now)
                    )
                    .font(
                        .system(
                            size: 86,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.top, 50)

                    Spacer(minLength: 0)
                }
                .frame(
                    width: phoneWidth,
                    height: 760
                )
                .zIndex(1)

                // MARK: Floating notification stack

                VStack(spacing: -42) {
                    ForEach(
                        Array(previews.enumerated()),
                        id: \.offset
                    ) { index, preview in

                        notificationBanner(preview)
                            .zIndex(Double(index))
                            .scaleEffect(
                                shownCards.contains(index)
                                    ? 1
                                    : 0.88,
                                anchor: .top
                            )
                            .opacity(
                                shownCards.contains(index)
                                    ? 1
                                    : 0
                            )
                            .offset(
                                y: shownCards.contains(index)
                                    ? 0
                                    : -30
                            )
                    }
                }
                .frame(width: geometry.size.width)
                .padding(.top, 245)
                .zIndex(10)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .top
            )
        }
        .frame(height: 500)
        .clipped()
    }

    // MARK: - Notification Banner

    private func notificationBanner(
        _ preview: NotificationPreview
    ) -> some View {
        HStack(spacing: 14) {

            // MARK: Partner avatar

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
            .frame(
                width: 48,
                height: 48
            )
            .clipShape(Circle())

            // MARK: Notification copy

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(preview.title)
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.black.opacity(0.82)
                    )
                    .lineLimit(1)

                Text(preview.body)
                    .font(
                        .system(
                            size: 16,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(
                        Color.black.opacity(0.52)
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(Color.white.opacity(0.98))
            .overlay {
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .strokeBorder(
                    Color.black.opacity(0.06),
                    lineWidth: 1
                )
            }
            .shadow(
                color: Color.black.opacity(0.22),
                radius: 20,
                x: 0,
                y: 10
            )
        }
        .padding(.horizontal, 12)
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
