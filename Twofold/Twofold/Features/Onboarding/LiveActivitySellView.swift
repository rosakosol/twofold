//
//  LiveActivitySellView.swift
//  Twofold
//
//  Feature-education screen only — this doesn't call any real ActivityKit API itself (the CTA
//  just advances onboarding), but the mockup below is deliberately built to mirror the REAL
//  Live Activity's actual layout — `Twofold/LiveActivities/JourneyLockScreenView.swift` — so
//  what someone sees here is what they'll actually see on their Lock Screen once they track a
//  real flight, not a hand-drawn approximation of it.
//

import SwiftUI
import UIKit

struct LiveActivitySellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var cardVisible = false
    @State private var now = Date()

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    // Illustrative only (no real flight is booked during onboarding) — fixed to a real
    // long-haul route (Qantas' actual nonstop London–Perth service, matching the QF10 flight
    // number below) rather than derived from the couple's own cities, so this mock always shows
    // the same curated, deliberately impressive "16h 50m, halfway around the world" flight
    // regardless of where either partner actually lives.
    private let originCode = "LHR"
    private let destinationCode = "PER"

    /// Real (not device-timezone-relative) London/Perth local departure/arrival wall-clock
    /// times for this route — not run through `Text(date, style: .time)` like the real widget
    /// does, since that formats in the *device's* current timezone, which would show neither of
    /// these fixed clock times unless the device itself happened to be in that airport's zone.
    /// A literal display string is what actually renders "11:55 AM"/"11:45 AM" on every device.
    private let illustrativeDepartureLabel = "11:55 AM"
    private let illustrativeArrivalLabel = "11:45 AM"

    var body: some View {
        OnboardingScaffold(
            title: "Track each other's flights in real time",
            subtitle: "Follow your partner's flight from your Lock Screen with Live Activities.",
            content: {
                phoneMock
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15)) {
                            cardVisible = true
                        }
                    }
            },
            primaryTitle: "Continue",
            // Last of the two sell screens now — the memory screens (`memoriesSell`/`mapSell`/
            // `firstMemoryIntro`/`firstMemory`) moved ahead of both notification/Live Activity
            // sell screens, so this is what actually follows them.
            primaryAction: { onboarding.path.append(.twofoldPreview) }
        )
    }

    // MARK: - Phone Mock

    /// Same oversized Lock Screen chassis `NotificationsSellView` uses, so the two Lock-Screen
    /// sell screens read as one consistent visual language rather than each inventing its own
    /// phone frame. The Live Activity card floats over it — wider than the chassis itself and
    /// carrying a real drop shadow, so it reads as "popping out" toward the viewer the way a
    /// real Live Activity visually sits above the rest of the Lock Screen content.
    private var phoneMock: some View {
        LockScreenPhoneMock(now: now) {
            lockScreenMock
                .padding(.horizontal, 10)
                // Matches `NotificationsSellView`'s own top offset against the same 500pt-tall
                // chassis — was 270, which put the card's bottom edge too close to the pinned
                // Continue button below. Also gives more breathing room above the card itself.
                .padding(.top, 240)
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 16)
                .scaleEffect(cardVisible ? 1 : 0.85)
                .opacity(cardVisible ? 1 : 0)
                .offset(y: cardVisible ? 0 : 16)
        }
    }

    /// A copy of `JourneyLockScreenView`'s real layout, with the same sizes and weights: the
    /// partner's photo and "<name> is on the way", the countdown in the accent on the right, the
    /// progress bar, and both airports. The system supplies a real Live Activity's dark blurred
    /// backdrop and rounded clip; `.regularMaterial` forced dark stands in for it here, since an
    /// onboarding screen has no ActivityKit presentation to inherit one from.
    private var lockScreenMock: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                partnerAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName) is on the way")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("QF10 to Perth")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                // Consistent with the progress bar below: 45% of the 16h 50m flight left.
                VStack(alignment: .trailing, spacing: 0) {
                    Text("7h 35m")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("to landing")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            progressBar

            HStack {
                airport(code: originCode, time: illustrativeDepartureLabel)
                Spacer(minLength: 8)
                airport(code: destinationCode, time: illustrativeArrivalLabel)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// The Live Activity's one accent, the same value `LiveActivityPalette.liveActivityAccent` uses.
    private var accent: Color { Color(hex: 0x6AA5F5) }

    /// The photo they added for their partner a few screens back, or their initial.
    @ViewBuilder
    private var partnerAvatar: some View {
        Group {
            if let data = onboarding.partnerPhotoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Theme.coralFill)
                    Text(String(partnerName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }

    private func airport(code: String, time: String) -> some View {
        HStack(spacing: 5) {
            Text(code)
                .font(.system(size: 17, weight: .semibold))
            Text(time)
                .font(.system(size: 17))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    /// The real card's bar, at 0.55 of the way: static, because a Live Activity only changes when
    /// its state does.
    private var progressBar: some View {
        GeometryReader { geo in
            let x = geo.size.width * 0.55
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                Capsule().fill(accent).frame(width: x, height: 4)
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0F16))
                    .frame(width: 26, height: 26)
                    .background(accent, in: Circle())
                    .position(x: x, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 26)
    }
}

#Preview {
    NavigationStack {
        LiveActivitySellView()
    }
    .environment(OnboardingModel())
}
