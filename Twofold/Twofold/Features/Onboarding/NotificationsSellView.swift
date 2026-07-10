//
//  NotificationsSellView.swift
//  Twofold
//
//  Sells the benefit before ever showing the system prompt. The native permission dialog
//  only appears once the user taps "Keep me updated" — if they deny it, onboarding just
//  continues normally and Twofold never asks again. Restyled around a dark Lock Screen
//  mockup (matching a real notification stack) rather than a plain list of cards, while
//  keeping the rest of the screen in Twofold's own light onboarding chrome.
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

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Explicit "h:mm" (12-hour, no leading zero, no AM/PM) rather than a locale-driven
    /// FormatStyle — omitting AM/PM there falls back to 24-hour ("03:36") on this device's
    /// locale, which doesn't match a real Lock Screen clock's look ("9:41").
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var partnerImage: Image? {
        onboarding.partnerPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

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
            subtitle: "Get flight updates when they matter, without constantly checking.",
            content: {
                phoneMock
                    .onAppear {
                        for index in previews.indices {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.68).delay(0.3 + Double(index) * 0.5)) {
                                _ = shownCards.insert(index)
                            }
                        }
                    }
            },
            primaryTitle: "Keep me updated",
            primaryAction: requestPermission,
            primaryDisabled: isRequesting
        )
        .sensoryFeedback(.impact(weight: .light), trigger: shownCards)
        .onReceive(clock) { now = $0 }
    }

    private var phoneMock: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 3)

                VStack(spacing: Theme.Spacing.lg) {
                    Text(Self.clockFormatter.string(from: now))
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, Theme.Spacing.xl + Theme.Spacing.sm)

                    VStack(spacing: -34) {
                        ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                            notificationBanner(preview)
                                .zIndex(shownCards.contains(index) ? Double(index) + 10 : Double(index))
                                .scaleEffect(shownCards.contains(index) ? 1 : 0.85, anchor: .top)
                                .opacity(shownCards.contains(index) ? 1 : 0)
                                .offset(y: shownCards.contains(index) ? 0 : -30)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)

                    Spacer(minLength: 0)
                }

                // Dynamic Island — purely decorative, sits on top of everything else.
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .frame(width: 100, height: 30)
                    .padding(.top, Theme.Spacing.md)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))

            Text("Shown on your Lock Screen")
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func notificationBanner(_ preview: NotificationPreview) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ZStack {
                if let partnerImage {
                    partnerImage.resizable().scaledToFill()
                } else {
                    Circle().fill(Theme.skyBlue.opacity(0.2))
                    Text(preview.emoji).font(.title3)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(preview.title).font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                Text(preview.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
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
