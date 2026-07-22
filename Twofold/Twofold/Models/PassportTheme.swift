//
//  PassportTheme.swift
//  Twofold
//
//  Shared palette for everything styled like the actual travel document — the Passport card on
//  the Stats tab and its full-page share card (`PassportShareCard`). Brand-blue cover (built on
//  `Theme.skyBlue`'s hue, not a generic navy) with gold foil and cream paper, plus a holographic
//  foil finish (`PassportHolographicBackground`). Deliberately kept dark enough end-to-end for
//  the gold/cream text on top of it to stay legible — an earlier pass leaned the top of the
//  gradient all the way to the bright on-brand `Theme.skyBlue` and ran the foil wash additively
//  (`.plusLighter`), which washed out contrast badly; this keeps the blue-family identity while
//  never letting the surface get light enough to fight white/gold text.
//

import SwiftUI

enum PassportTheme {
    static let coverTop = Color(hex: "1D5CA3")
    static let coverBottom = Color(hex: "081B33")
    static let gold = Color(hex: "D8B463")
    static let cream = Color(hex: "F3ECD9")
}

/// The cover's full background: brand-blue gradient, a soft top highlight, a holographic foil
/// tint (`.overlay` blend — tints hue without uniformly brightening the way `.plusLighter` did),
/// and a single diagonal shimmer that sweeps across once when the card first appears — the
/// "catches the light" moment real foil has, without an always-on looping animation competing
/// for attention on a screen that's visible most of the time someone's on the Stats tab.
struct PassportHolographicBackground: View {
    @State private var shimmerOffset: CGFloat = -1.3

    private static let foilColors: [Color] = [
        Color(hex: "FF9FE5"), Color(hex: "9FE9FF"), Color(hex: "B9FFDA"), Color(hex: "FFF3A0"), Color(hex: "FF9FE5"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [PassportTheme.coverTop, PassportTheme.coverBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.08), .clear], center: .top, startRadius: 10, endRadius: 340)

            LinearGradient(colors: Self.foilColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.16)
                .blendMode(.overlay)

            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: geo.size.width * 0.55)
                    .rotationEffect(.degrees(18))
                    .offset(x: geo.size.width * shimmerOffset)
                    .blendMode(.overlay)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).delay(0.25)) {
                shimmerOffset = 1.3
            }
        }
    }
}

/// The ICAO biometric-passport cover symbol — a small rounded outline with a chip/aperture
/// circle at its center, printed on the front of every real e-passport. Stands in for the
/// generic seal/emblem icon a placeholder passport card would otherwise use.
struct BiometricPassportSymbol: View {
    var color: Color = PassportTheme.gold
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .stroke(color, lineWidth: max(1, size * 0.09))
                .frame(width: size, height: size * 0.7)
            Circle()
                .stroke(color, lineWidth: max(1, size * 0.07))
                .frame(width: size * 0.32, height: size * 0.32)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    BiometricPassportSymbol(size: 60)
        .padding()
        .background(PassportTheme.coverBottom)
}
