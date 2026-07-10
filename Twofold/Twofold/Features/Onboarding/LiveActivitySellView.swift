//
//  LiveActivitySellView.swift
//  Twofold
//
//  Feature-education screen only — Twofold has no working Live Activity implementation
//  yet (that needs a separate Widget Extension target and real ActivityKit code), so the
//  CTA here just advances onboarding rather than calling any real API. The moment-by-moment
//  journey timeline that used to live on this mockup now belongs to the real flight-tracking
//  screen instead (`FlightTrackingView`'s timeline + self-reported updates), not onboarding.
//

import SwiftUI
import UIKit

struct LiveActivitySellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var pulsePhase: CGFloat = 1
    @State private var cardVisible = false

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

    /// Real math against the real cities picked earlier in onboarding, not an invented number.
    private var distanceKm: Double? {
        guard let originCity, let destinationCity else { return nil }
        return Geo.distanceKm(originCity.coordinate, destinationCity.coordinate)
    }

    private var partnerImage: Image? {
        onboarding.partnerPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    var body: some View {
        OnboardingScaffold(
            title: "Keep \(partnerName.prefix(1).uppercased() + partnerName.dropFirst())'s journey close",
            subtitle: "Follow \(partnerName)'s flight from your Lock Screen with Live Activities.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    lockScreenMock
                        .scaleEffect(cardVisible ? 1 : 0.85)
                        .opacity(cardVisible ? 1 : 0)
                        .offset(y: cardVisible ? 0 : 16)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                        cardVisible = true
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.memoriesSell) }
        )
    }

    /// Modeled on a real Live Activity's compact-info layout — flight number up top, a big
    /// centered time-remaining readout with distance, then big airport codes either side of
    /// the route. No arrival terminal/gate/bag claim row, since Twofold has none of that
    /// data to show.
    private var lockScreenMock: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("QF9")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.caption2)
                    Text("On time")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.15), in: Capsule())
            }

            VStack(spacing: 2) {
                Text("2h 14m")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let distanceKm {
                    Text("to go · \(distanceKm.formatted(.number.precision(.fractionLength(0)))) km")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(originCode)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("6:30 PM")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                flightPath
                    .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(destinationCode)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("2:30 AM")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Text("Updated just now")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { skyBackground }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Dusk sky gradient with a faint airplane silhouette, standing in for the aircraft photo
    /// a real Live Activity background would use — a dark overlay keeps the existing white
    /// text readable on top of it, same contrast the plain black background had.
    private var skyBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1B2A4A"), Color(hex: "3E5C8A"), Color(hex: "C97B5A")],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "airplane")
                .font(.system(size: 130))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-45))
                .offset(x: 60, y: -30)
            Color.black.opacity(0.28)
        }
    }

    /// Solid line for distance already flown, dashed for what's left, with a hollow ring at
    /// the destination — same visual language real flight-tracking Live Activities use. The
    /// badge marking the current position shows the partner's own photo when one was picked
    /// earlier in onboarding, falling back to a plane icon otherwise.
    private var flightPath: some View {
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
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

                Circle()
                    .stroke(.white.opacity(0.4), lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .position(x: geo.size.width, y: midY)

                ZStack {
                    if let partnerImage {
                        partnerImage.resizable().scaledToFill()
                    } else {
                        Circle().fill(Theme.skyBlue)
                        Image(systemName: "airplane")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .scaleEffect(pulsePhase)
                .position(x: progressX, y: midY)
            }
        }
        .frame(height: 26)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePhase = 1.12
            }
        }
    }
}

#Preview {
    NavigationStack {
        LiveActivitySellView()
    }
    .environment(OnboardingModel())
}
