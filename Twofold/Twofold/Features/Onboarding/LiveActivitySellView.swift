//
//  LiveActivitySellView.swift
//  Twofold
//
//  Feature-education screen only — Twofold has no working Live Activity implementation
//  yet (that needs a separate Widget Extension target and real ActivityKit code), so the
//  CTA here just advances onboarding rather than calling any real API.
//

import SwiftUI

private struct JourneyMoment {
    let emoji: String
    let title: String
    let subtitle: String
    let timestamp: String
}

struct LiveActivitySellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var pulsePhase: CGFloat = -1
    @State private var timelineVisible = false

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    /// Illustrative only — there's no real flight-status feed behind this (see the note on
    /// the type doc above), just a sense of the range of moments Twofold can surface.
    private var journeyMoments: [JourneyMoment] {
        [
            JourneyMoment(
                emoji: "🛫",
                title: "\(partnerName) departed",
                subtitle: "QF9 departed Melbourne (MEL).",
                timestamp: "6:48 PM"
            ),
            JourneyMoment(
                emoji: "☁️",
                title: "In the air",
                subtitle: "Cruising at 35,000 ft.",
                timestamp: "7:20 PM"
            ),
            JourneyMoment(
                emoji: "🍽️",
                title: "Meal service",
                subtitle: "Dinner service has started.",
                timestamp: "8:15 PM"
            ),
            JourneyMoment(
                emoji: "😴",
                title: "Time to relax",
                subtitle: "Lights dimmed — time for \(partnerName) to rest.",
                timestamp: "10:40 PM"
            ),
            JourneyMoment(
                emoji: "🛬",
                title: "\(partnerName) is landing soon",
                subtitle: "Touch down is in an hour.",
                timestamp: "1:48 AM"
            ),
            JourneyMoment(
                emoji: "🎉",
                title: "\(partnerName) has landed!",
                subtitle: "QF9 has arrived safely in London.",
                timestamp: "2:48 AM"
            ),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            title: "Keep \(partnerName.prefix(1).uppercased() + partnerName.dropFirst())'s journey close.",
            subtitle: "Follow \(partnerName)'s flight from your Lock Screen without opening Twofold.",
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        lockScreenMock
                        Text("Available with Live Activities")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("EVERY MOMENT OF THE JOURNEY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.subtleInk)

                        SectionCard {
                            VStack(spacing: 0) {
                                ForEach(Array(journeyMoments.enumerated()), id: \.offset) { index, moment in
                                    journeyRow(moment, isLast: index == journeyMoments.count - 1)
                                        .opacity(timelineVisible ? 1 : 0)
                                        .offset(x: timelineVisible ? 0 : -16)
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.08),
                                            value: timelineVisible
                                        )
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        pulsePhase = 1
                    }
                    timelineVisible = true
                }
            },
            primaryTitle: "Follow their journey",
            primaryAction: { onboarding.path.append(.addFirstFlight) }
        )
    }

    private var lockScreenMock: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("\(partnerName) is on the way ❤️")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: Theme.Spacing.sm) {
                cityBadge(code: "MEL", gradient: [Theme.skyBlue, Theme.leafGreen])
                flightPath
                cityBadge(code: "LHR", gradient: [Theme.heartRed, .orange])
            }

            HStack {
                Text("2h 14m to go")
                Spacer()
                Text("QF9 · On time")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Stands in for a real city photo — there's no photo source for arbitrary cities, so
    /// each gets a distinct gradient globe badge instead of a fabricated image.
    private func cityBadge(code: String, gradient: [Color]) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            Text(code)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var flightPath: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Theme.skyBlue, .white, Theme.skyBlue, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: pulsePhase * geo.size.width)
                }
                .frame(height: 4)
                .clipShape(Capsule())

                ZStack {
                    Circle().fill(Theme.skyBlue)
                    Image(systemName: "airplane")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 34)
    }

    /// A real connecting rail links each emoji badge to the next, like a vertical timeline.
    /// Every badge uses the same neutral tint — the emoji itself carries the color, so the
    /// row doesn't need a different background per moment too.
    private func journeyRow(_ moment: JourneyMoment, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.12))
                    Text(moment.emoji).font(.system(size: 18))
                }
                .frame(width: 40, height: 40)

                if !isLast {
                    Rectangle()
                        .fill(Theme.subtleInk.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moment.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(moment.timestamp)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }
                Text(moment.subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 0 : Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        LiveActivitySellView()
    }
    .environment(OnboardingModel())
}
