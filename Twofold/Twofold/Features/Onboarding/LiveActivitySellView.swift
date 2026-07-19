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

    // CoupleLocationsView requires both cities before you can advance, so these are always
    // real by the time this screen runs — the illustrative flight runs partner's city →
    // user's city, matching the "reunion" framing used throughout onboarding.
    // `illustrativeOriginCity` swaps in a random other city if the couple lives in the same
    // place (same cached value the notifications sell screen reads, so the two stay
    // consistent) — otherwise this example flight would depart and arrive in the same city.
    private var originCity: Place? { onboarding.illustrativeOriginCity }
    private var destinationCity: Place? { onboarding.homeCity }

    private var originCode: String {
        originCity?.iataCode?.uppercased() ?? originCity?.city.uppercased() ?? "———"
    }

    private var destinationCode: String {
        destinationCity?.iataCode?.uppercased() ?? destinationCity?.city.uppercased() ?? "———"
    }

    /// One shared size for both airport codes, picked from whichever of the two strings is
    /// longer — a real IATA code (3 letters) always gets the full 22pt, but if either city
    /// falls back to its full name (no IATA code on file), *both* columns step down together
    /// instead of just the long one shrinking on its own and reading as mismatched.
    private var airportCodeFontSize: CGFloat {
        switch max(originCode.count, destinationCode.count) {
        case ...4: 22
        case 5...6: 18
        case 7...9: 15
        default: 12
        }
    }

    /// Illustrative only (no real flight is booked during onboarding) — a departure ~40 minutes
    /// ago and an arrival ~2h14m from now, matching the illustrative countdown below. Still run
    /// through `Text(date, style: .time)`, the same real, localized time formatting
    /// `JourneyLockScreenView` uses, rather than a hardcoded time string.
    private var illustrativeDeparture: Date { Date.now.addingTimeInterval(-40 * 60) }
    private var illustrativeArrival: Date { Date.now.addingTimeInterval((2 * 60 + 14) * 60) }

    var body: some View {
        OnboardingScaffold(
            title: "Keep \(partnerName.prefix(1).uppercased() + partnerName.dropFirst())'s journey close",
            subtitle: "Follow \(partnerName)'s flight from your Lock Screen with Live Activities.",
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
                .padding(.top, 270)
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
                    Text("QF9")
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
                Text("2h 14m left")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("\(partnerName) is on the way to you ❤️")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: 10) {
                airportColumn(code: originCode, time: illustrativeDeparture, alignment: .leading)
                progressRail
                airportColumn(code: destinationCode, time: illustrativeArrival, alignment: .trailing)
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

    private func airportColumn(code: String, time: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.system(size: airportCodeFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(time, style: .time)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(minWidth: 60, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// Identical to the real Live Activity's progress rail — solid tint up to progress, dashed
    /// remainder, a plain icon-in-circle riding the progress point. No pulse/scale animation:
    /// WidgetKit's Live Activity views are effectively static (system-driven state updates only),
    /// so a continuously-animating badge here would show something the real one never does.
    private var progressRail: some View {
        GeometryReader { geo in
            let progressX = geo.size.width * 0.4
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
