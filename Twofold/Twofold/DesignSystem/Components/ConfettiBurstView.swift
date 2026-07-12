//
//  ConfettiBurstView.swift
//  Twofold
//
//  Lightweight confetti burst — a fixed set of particles animate outward and down from the
//  center with random rotation/opacity once `trigger` fires. No third-party dependency; simple
//  enough that a lookup table of pre-randomized offsets beats a per-frame particle system.
//  Shared between onboarding's TwofoldPreviewView and PartnerConnectedView.
//

import SwiftUI

struct ConfettiBurstView: View {
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
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
