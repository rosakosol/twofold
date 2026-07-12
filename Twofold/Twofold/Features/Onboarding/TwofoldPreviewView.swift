//
//  TwofoldPreviewView.swift
//  Twofold
//
//  Reflects back exactly what's been entered so far — no fabricated countdown or flight
//  when nothing was added. Reached only after either a real flight or a real memory has been
//  added (the flight step's own skip lands on the mandatory memory step instead), so there's
//  always something real to celebrate — hence the confetti + congrats treatment, reusing the
//  same celebration pattern as PurchaseSuccessView (spring-scaled centerpiece + success haptic)
//  rather than inventing a new one.
//

import SwiftUI
import UIKit

struct TwofoldPreviewView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var didCelebrate = false
    @State private var heartScale: CGFloat = 0.6

    private var trip: Trip? { appModel.upcomingTrips.first }

    private var daysToGo: Int? {
        guard let trip else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    private var sameCity: Bool {
        guard let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return false }
        return mine.city == theirs.city && mine.country == theirs.country
    }

    private var distanceKm: Double? {
        guard !sameCity, let mine = onboarding.homeCity?.coordinate, let theirs = onboarding.partnerCity?.coordinate else { return nil }
        return Geo.distanceKm(mine, theirs)
    }

    private var daysTogether: Int? {
        guard let anniversaryDate = onboarding.anniversaryDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0)
    }

    private var selfImage: Image? {
        onboarding.selfPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    private var partnerImage: Image? {
        onboarding.partnerPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    var body: some View {
        OnboardingScaffold(
            title: "Your Twofold is ready ❤️",
            subtitle: "You're all set — here's to closing the distance.",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    Text("🎉")
                        .font(.system(size: 64))
                        .scaleEffect(heartScale)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            ConfettiBurstView(trigger: didCelebrate)
                        }
                        .onAppear {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                heartScale = 1.0
                            }
                            didCelebrate = true
                        }

                    SectionCard {
                        HStack {
                            VStack(spacing: 6) {
                                avatarCircle(selfImage)
                                Text(onboarding.firstName.isEmpty ? "You" : onboarding.firstName).font(.headline)
                                if let city = onboarding.homeCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                            Spacer()
                            Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed)
                            Spacer()
                            VStack(spacing: 6) {
                                avatarCircle(partnerImage)
                                Text(onboarding.partnerName.isEmpty ? "Partner" : onboarding.partnerName).font(.headline)
                                if let city = onboarding.partnerCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let trip, let daysToGo {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next reunion")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.subtleInk)
                                    Text(daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go")
                                        .font(.title2.weight(.bold))
                                    if let flight = trip.flight {
                                        Text("\(flight.flightNumber) · \(trip.origin.city) → \(trip.destination.city)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if daysTogether != nil || distanceKm != nil {
                        SectionCard {
                            HStack(spacing: Theme.Spacing.lg) {
                                if let daysTogether {
                                    StatTile(icon: "heart.fill", value: "\(daysTogether)", label: "Days together", tint: Theme.heartRed)
                                }
                                if let distanceKm {
                                    StatTile(
                                        icon: "globe",
                                        value: "\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km",
                                        label: "Apart",
                                        tint: Theme.skyBlue
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No trips yet")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Add a flight anytime to start your countdown.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.saveAccount) }
        )
        .sensoryFeedback(.success, trigger: didCelebrate)
    }

    private func avatarCircle(_ image: Image?) -> some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Theme.cardBackground)
                Image(systemName: "person.fill").foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}

/// Lightweight confetti burst — a fixed set of particles animate outward and down from the
/// center with random rotation/opacity once `trigger` fires. No third-party dependency; simple
/// enough that a lookup table of pre-randomized offsets beats a per-frame particle system.
private struct ConfettiBurstView: View {
    let trigger: Bool
    @State private var animate = false

    private struct Particle {
        let dx: CGFloat
        let dy: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
    }

    private static let colors: [Color] = [Theme.heartRed, Theme.skyBlue, Theme.leafGreen, .yellow, .purple, .orange]

    private static let particles: [Particle] = (0..<24).map { index in
        var generator = SeededGenerator(seed: index)
        let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
        let distance = CGFloat.random(in: 70...150, using: &generator)
        return Particle(
            dx: cos(angle) * distance,
            dy: sin(angle) * distance - 40,
            rotation: Double.random(in: 0...540, using: &generator),
            color: colors[index % colors.count],
            delay: Double.random(in: 0...0.15, using: &generator)
        )
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.particles.enumerated()), id: \.offset) { _, particle in
                RoundedRectangle(cornerRadius: 2)
                    .fill(particle.color)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(animate ? particle.rotation : 0))
                    .offset(x: animate ? particle.dx : 0, y: animate ? particle.dy : 0)
                    .opacity(animate ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            animate = false
            withAnimation(.easeOut(duration: 0.9)) {
                animate = true
            }
        }
    }
}

/// Deterministic RNG so the confetti layout is computed once as a `static let` instead of
/// re-randomizing (and re-laying-out) on every view update.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

#Preview {
    NavigationStack {
        TwofoldPreviewView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
