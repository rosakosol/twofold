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
    @State private var pulsePhase: CGFloat = 1
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
                    timelineVisible = true
                }
            },
            primaryTitle: "Follow their journey",
            primaryAction: { onboarding.path.append(.widgetSell) }
        )
    }

    /// Modeled on a real Live Activity's compact-info layout (airline + duration pill up top,
    /// big airport codes either side of the route, a status caption underneath) rather than
    /// the app's earlier from-scratch mock — no arrival terminal/gate/bag claim row, since
    /// Twofold has none of that data to show.
    private var lockScreenMock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Text("Qantas")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("❤️").font(.caption)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.caption2)
                    Text("2h 14m")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.15), in: Capsule())
            }

            Text("QF9")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEL")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("6:48 PM")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

                flightPath
                    .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("LHR")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("2:48 AM")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Text("Updated just now")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Solid line for distance already flown, dashed for what's left, with a small plane
    /// badge marking the current position and a hollow ring at the destination — the same
    /// visual language real flight-tracking Live Activities use.
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
                    Circle().fill(Theme.skyBlue)
                    Image(systemName: "airplane")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 2))
                .scaleEffect(pulsePhase)
                .position(x: progressX, y: midY)
            }
        }
        .frame(height: 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePhase = 1.12
            }
        }
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
