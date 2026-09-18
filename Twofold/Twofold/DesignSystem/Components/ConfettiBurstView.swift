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

enum ConfettiStyle {
    /// Radiates from the centre of whatever it is given. The default, because it is what the two
    /// existing callers want and are sized for.
    case burst
    /// Falls across the full width, top to bottom. For a full-screen celebration.
    case shower
}

struct ConfettiBurstView: View {
    let trigger: Bool
    var style: ConfettiStyle = .burst
    // Starts `true` (i.e. "already at rest, post-burst": offset out, opacity 0) rather than
    // `false` — with `false` as the initial value, every particle sat at opacity 1 stacked
    // exactly on top of each other at the center (offset 0,0) until the first real trigger, which
    // for any result screen that never actually bursts confetti (every Trivia result, or a
    // match-game result under the 80% threshold) meant a small stray dot — the last-drawn
    // particle's color (orange) showing through the stack — sat permanently in the middle of the
    // screen. `onChange(of: trigger)` already snaps back to the center before animating back out
    // on every real trigger, so this only changes what shows up before the first (or with no)
    // trigger.
    @State private var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle {
        let dx: CGFloat
        let dy: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
    }

    private static let colors: [Color] = [Theme.heartRed, Theme.skyBlue, Theme.leafGreen, .yellow, .purple, .orange]

    /// One generator for the whole table, not one per particle.
    ///
    /// This was `SeededGenerator(seed: index)` inside the map, so every particle drew its angle
    /// from a generator whose state was the constant plus a number from 0 to 23. Xorshift on
    /// states that close together returns first outputs that close together: all twenty-four
    /// particles came out at 310 degrees, and the "burst" was a single straight stream. Drawing
    /// the whole table from one generator spreads them across every quadrant, and is still
    /// deterministic — which is the only reason the per-particle seeding existed.
    private static let particles: [Particle] = {
        var generator = SeededGenerator(seed: 1)
        return (0..<24).map { index in
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
    }()

    /// Falls from above the top edge to below the bottom one, spread across the full width.
    ///
    /// A burst radiating from the middle is right for a small celebration area — the 180pt block
    /// `PartnerConnectedView` gives it — and wrong for "shower the screen", which is what a
    /// full-bleed finish wants. Same colours, different physics.
    private struct ShowerParticle {
        let x: CGFloat
        let drift: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
        let duration: Double
    }

    private static let showerParticles: [ShowerParticle] = {
        var generator = SeededGenerator(seed: 7)
        return (0..<48).map { index in
            ShowerParticle(
                x: CGFloat.random(in: 0.02...0.98, using: &generator),
                drift: CGFloat.random(in: -40...40, using: &generator),
                rotation: Double.random(in: 180...900, using: &generator),
                color: colors[index % colors.count],
                delay: Double.random(in: 0...1.1, using: &generator),
                duration: Double.random(in: 1.8...3.0, using: &generator)
            )
        }
    }()

    var body: some View {
        switch style {
        case .burst: burstBody
        case .shower: showerBody
        }
    }

    private var showerBody: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(Self.showerParticles.enumerated()), id: \.offset) { _, particle in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(particle.color)
                        .frame(width: 7, height: 12)
                        .rotationEffect(.degrees(animate ? particle.rotation : 0))
                        .position(
                            x: particle.x * max(geo.size.width, 1) + (animate ? particle.drift : 0),
                            y: animate ? geo.size.height + 60 : -60
                        )
                        // Per-particle timing, which is what makes it a shower rather than
                        // everything arriving at once.
                        .animation(
                            reduceMotion ? nil : .easeIn(duration: particle.duration).delay(particle.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            // The reset has to land un-animated, or the particles visibly fly back up before
            // falling again. `.animation(_:value:)` above would otherwise animate both directions.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { animate = false }
            Task { @MainActor in animate = true }
        }
    }

    private var burstBody: some View {
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
            // Purely celebratory, no information conveyed by the motion itself — skip the burst
            // entirely under Reduce Motion rather than trying to tone it down.
            guard !reduceMotion else { return }
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
