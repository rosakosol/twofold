//
//  BrandLoadingView.swift
//  Twofold
//
//  Replaces the bare ProgressView() RootView showed while AppModel.restoreSession() is in
//  flight — same GlobeHeart + "twofold" wordmark pairing as TwofoldBrandMark, but animated for
//  a launch moment rather than static like that view's shareable-image header use.
//
//  The beating mark itself is `PulsingGlobeHeart` now, shared with the onboarding screens that
//  wanted the same heartbeat without a wordmark. Its 1.1s pulse matches WelcomeView's and
//  TrialTrustView's, so the logo doesn't change rhythm the moment restoreSession() finishes and
//  one screen gives way to another. What stays here is the wordmark and its one-time fade.
//

import SwiftUI

struct BrandLoadingView: View {
    @State private var wordmarkVisible = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            PulsingGlobeHeart()

            Text("twofold")
                .font(.system(.title, design: .serif))
                .foregroundStyle(Theme.ink)
                .opacity(wordmarkVisible ? 1 : 0)
                .offset(y: wordmarkVisible ? 0 : 6)
        }
        .onAppear {
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
