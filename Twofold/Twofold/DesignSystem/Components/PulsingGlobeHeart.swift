//
//  PulsingGlobeHeart.swift
//  Twofold
//
//  The brand mark, beating.
//
//  Pulled out of `BrandLoadingView`, which had the only copy of this and wrapped it in a wordmark
//  and a launch-specific fade. Onboarding wants the same heartbeat without either — above the line
//  telling someone their partner invited them, and standing in for a face nobody has chosen yet.
//
//  The timing is `BrandLoadingView`'s, unchanged: 1.1s easeInOut, repeating, autoreversing. That
//  number is load-bearing rather than arbitrary — it already matched WelcomeView's and
//  TrialTrustView's pulses so the mark does not visibly change rhythm when one screen replaces
//  another, and onboarding now moves between several screens that show it.
//

import SwiftUI

struct PulsingGlobeHeart: View {
    var size: CGFloat = 88
    /// The soft halo behind the mark. Off where the heart sits in a tight row or beside text at
    /// small sizes, where a blurred circle reads as a smudge rather than a glow.
    var showsGlow: Bool = true

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(Theme.skyBlue.opacity(0.25))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .blur(radius: size * 0.2)
                    .scaleEffect(isPulsing ? 1.08 : 0.92)
                    .opacity(isPulsing ? 0.9 : 0.4)
            }

            Image("GlobeHeart")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 1.08 : 1.0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        // One mark, however many screens it appears on — VoiceOver should hear it named once and
        // not have the glow and the image read as two things.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Twofold")
    }
}

#Preview {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 48) {
            PulsingGlobeHeart()
            PulsingGlobeHeart(size: 56, showsGlow: false)
        }
    }
}
