//
//  AnimatedBalloonsView.swift
//  Twofold
//
//  Ambient balloons drifting upward behind `HappyBirthdayView`, built on exactly the pattern
//  `AnimatedHeartsView` established: positions, sizes and timings randomised once through
//  `SeededGenerator` rather than a per-frame particle system, and every balloon parked at a fixed
//  spot under Reduce Motion because none of the movement carries information.
//
//  Its own view rather than a `symbol:` parameter on the hearts one. They differ in more than the
//  glyph — balloons are tinted and sway, hearts are white and rise straight — and threading three
//  behaviours through the existing view to avoid one file would leave both harder to read than
//  they are apart.
//

import SwiftUI

struct AnimatedBalloonsView: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Balloon {
        let xFraction: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
        let opacity: Double
        let hue: Double
        let sway: CGFloat
    }

    private static let balloons: [Balloon] = (0..<16).map { index in
        var generator = SeededGenerator(seed: index + 2000)
        return Balloon(
            xFraction: CGFloat.random(in: 0.05...0.95, using: &generator),
            size: CGFloat.random(in: 18...38, using: &generator),
            duration: Double.random(in: 5.0...9.0, using: &generator),
            delay: Double.random(in: 0...3.5, using: &generator),
            opacity: Double.random(in: 0.35...0.85, using: &generator),
            hue: Double.random(in: 0...1, using: &generator),
            sway: CGFloat.random(in: -18...18, using: &generator)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(Self.balloons.enumerated()), id: \.offset) { _, balloon in
                    Image(systemName: "balloon.fill")
                        .font(.system(size: balloon.size))
                        // Saturated but not fully — fully saturated hues across a random spread
                        // include several that vibrate against the purple/amber gradient behind.
                        .foregroundStyle(Color(hue: balloon.hue, saturation: 0.55, brightness: 1).opacity(balloon.opacity))
                        .position(
                            x: balloon.xFraction * geo.size.width + (animate && !reduceMotion ? balloon.sway : 0),
                            y: reduceMotion ? geo.size.height * 0.5 : (animate ? -50 : geo.size.height + 50)
                        )
                        .animation(
                            reduceMotion ? nil : .linear(duration: balloon.duration).repeatForever(autoreverses: false).delay(balloon.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { animate = true }
    }
}

#Preview {
    ZStack {
        Theme.coralGradient
            .ignoresSafeArea()
        AnimatedBalloonsView()
    }
}
