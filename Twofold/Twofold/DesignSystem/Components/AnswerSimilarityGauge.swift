//
//  AnswerSimilarityGauge.swift
//  Twofold
//
//  Animated half-circle gauge for a couple's match percentage on This or That / Who's More
//  Likely To results — the arc fills from 0 to the final percentage so the number feels earned
//  rather than just appearing. `.contentTransition(.numericText())` gives the percent label its
//  own rolling count-up during that same animation, no custom Animatable wrapper needed.
//

import SwiftUI

struct AnswerSimilarityGauge: View {
    let percent: Int
    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            arc(fraction: 1, color: Theme.cardBackground)
            arc(fraction: animatedFraction, color: tint)

            VStack(spacing: 2) {
                Text("\(Int((animatedFraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("answer similarity")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .frame(width: 200, height: 110)
        .onAppear {
            animatedFraction = 0
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) {
                animatedFraction = Double(percent) / 100
            }
        }
    }

    private var tint: Color {
        switch percent {
        case 80...: Theme.leafGreen
        case 50..<80: Theme.skyBlue
        default: Theme.heartRed
        }
    }

    private func arc(fraction: Double, color: Color) -> some View {
        HalfCircleArc(fraction: fraction)
            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
    }
}

/// A half-circle (180°) gauge track, sweeping left-to-right along the top — `fraction` is
/// `animatableData` so SwiftUI interpolates it per-frame during a `withAnimation` block.
private struct HalfCircleArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2, rect.height) - 7
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 - 180 * fraction),
            clockwise: true
        )
        return path
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        AnswerSimilarityGauge(percent: 92)
        AnswerSimilarityGauge(percent: 55)
        AnswerSimilarityGauge(percent: 20)
    }
    .padding()
    .background(Theme.backgroundGradient)
}
