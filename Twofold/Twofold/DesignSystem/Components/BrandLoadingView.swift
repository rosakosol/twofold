//
//  BrandLoadingView.swift
//  Twofold
//
//  Replaces the bare ProgressView() RootView showed while AppModel.restoreSession() is in
//  flight — same GlobeHeart + "twofold" wordmark pairing as TwofoldBrandMark, but animated for
//  a launch moment rather than static like that view's shareable-image header use. The pulse
//  timing (1.1s easeInOut, repeatForever, autoreverses) matches WelcomeView/TrialTrustView's
//  existing GlobeHeart pulse exactly, so the logo doesn't visibly change rhythm the moment
//  restoreSession() finishes and WelcomeView potentially takes over.
//

import SwiftUI

struct BrandLoadingView: View {
    @State private var isPulsing = false
    @State private var wordmarkVisible = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.skyBlue.opacity(0.25))
                    .frame(width: 132, height: 132)
                    .blur(radius: 18)
                    .scaleEffect(isPulsing ? 1.08 : 0.92)
                    .opacity(isPulsing ? 0.9 : 0.4)

                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .scaleEffect(isPulsing ? 1.08 : 1.0)
            }

            Text("twofold")
                .font(.system(.title, design: .serif))
                .foregroundStyle(Theme.ink)
                .opacity(wordmarkVisible ? 1 : 0)
                .offset(y: wordmarkVisible ? 0 : 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            // A one-time fade-in, not looped with the pulse — the wordmark settling in place
            // once reads as "arriving," where looping it alongside the logo would just be noise.
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                wordmarkVisible = true
            }
        }
    }
}

#Preview {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        BrandLoadingView()
    }
}
