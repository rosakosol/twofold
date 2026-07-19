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
    private let airportCodeFontSize: CGFloat = 22

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
            primaryAction: { onboarding.path.append(.memoriesSell) }
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

    /// Line-for-line copy of `JourneyLockScreenView`'s real body — same spacing (12/18/8/2/10),
    /// same font sizes/weights, same `WidgetBrandMark` (plain 16×16 image, no badge — an earlier
    /// version of this mock wrapped it in a rounded-rect badge that the real one never had), same
    /// static (non-pulsing) progress-rail badge, so what someone sees here really is what they'll
    /// see on their Lock Screen once they track a real flight. The "Updated Xm ago" text the real
    /// widget shows is left out here — during onboarding there's no real update to report yet,
    /// and a fixed "just now" read as decorative rather than informative. The system itself
    /// supplies the blurred dark backdrop and rounded-corner clip for a real Live Activity —
    /// `.regularMaterial` forced to dark here approximates that, since a plain onboarding screen
    /// has no ActivityKit presentation context to inherit it from.
    private var lockScreenMock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // The real Qantas tailfin logo (QF9 is a real Qantas-operated route) — same
                // `AirlineLogoView` the live app uses everywhere else, rather than a generic
                // airplane glyph standing in for "some airline."
                AirlineLogoView(url: AirlineLogo.url(forIATACode: "QF"), size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("QF10")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Qantas")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                // Plain 16×16 image at 0.9 opacity, no badge/background — matches
                // `LiveActivities/WidgetBrandMark.swift` exactly (that target can't be imported
                // from the main app, so this is a literal copy of its three modifiers).
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .opacity(0.9)
            }

            VStack(alignment: .center, spacing: 2) {
                // Consistent with the progress rail below (0.55 elapsed of the 16h 50m total —
                // see its doc comment): 45% of 16h 50m remaining ≈ 7h 35m.
                Text("7h 35m left")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: 10) {
                airportColumn(code: originCode, time: illustrativeDepartureLabel, alignment: .leading)
                progressRail
                airportColumn(code: destinationCode, time: illustrativeArrivalLabel, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func airportColumn(code: String, time: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.system(size: airportCodeFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(time)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(minWidth: 60, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// Identical to the real Live Activity's progress rail — solid tint up to progress, dashed
    /// remainder, a plain icon-in-circle riding the progress point. No pulse/scale animation:
    /// WidgetKit's Live Activity views are effectively static (system-driven state updates only),
    /// so a continuously-animating badge here would show something the real one never does.
    ///
    /// 0.55 — comfortably past the midpoint of the 16h 50m illustrative flight, matching the
    /// "7h 35m left" headline above — rather than derived from any real elapsed time, since the
    /// departure/arrival labels are now fixed display strings, not real `Date`s to measure from.
    private var progressRail: some View {
        GeometryReader { geo in
            let progressX = geo.size.width * 0.55
            let midY = geo.size.height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: progressX, y: midY))
                }
                .stroke(Theme.skyBlue, lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: progressX, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

                Image(systemName: "airplane")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.skyBlue, in: Circle())
                    .position(x: progressX, y: midY)
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        LiveActivitySellView()
    }
    .environment(OnboardingModel())
}
