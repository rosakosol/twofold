//
//  AnimatedHeartsView.swift
//  Twofold
//
//  Ambient background of heart glyphs continuously drifting upward and fading, each on its own
//  staggered loop — used by HappyAnniversaryView. Positions/sizes/timings are pre-randomized
//  once via the same `SeededGenerator` pattern `ConfettiBurstView` already uses, rather than a
//  per-frame particle system.
//

import SwiftUI

struct AnimatedHeartsView: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Heart {
        let xFraction: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
        let opacity: Double
    }

    private static let hearts: [Heart] = (0..<14).map { index in
        var generator = SeededGenerator(seed: index + 1000)
        return Heart(
            xFraction: CGFloat.random(in: 0.05...0.95, using: &generator),
            size: CGFloat.random(in: 14...30, using: &generator),
            duration: Double.random(in: 4.5...7.5, using: &generator),
            delay: Double.random(in: 0...3, using: &generator),
            opacity: Double.random(in: 0.35...0.8, using: &generator)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(Self.hearts.enumerated()), id: \.offset) { _, heart in
                    Image(systemName: "heart.fill")
                        .font(.system(size: heart.size))
                        .foregroundStyle(.white.opacity(heart.opacity))
                        // Ambient decoration only, no information in the motion itself — under
                        // Reduce Motion the hearts stay put at a fixed spot instead of
                        // continuously drifting/looping.
                        .position(
                            x: heart.xFraction * geo.size.width,
                            y: reduceMotion ? geo.size.height * 0.5 : (animate ? -40 : geo.size.height + 40)
                        )
                        .animation(
                            reduceMotion ? nil : .linear(duration: heart.duration).repeatForever(autoreverses: false).delay(heart.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}

#Preview {
    ZStack {
        Theme.heartRed.ignoresSafeArea()
        AnimatedHeartsView()
    }
}
