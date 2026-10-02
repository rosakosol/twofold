//
//  ScreenBackground.swift
//  Twofold
//

import SwiftUI

/// Every screen's background (docs/TWOFOLD_DESIGN.md, sections 2.1 and 2.4): the blue-to-green wash
/// in light mode or `#0B0F16` in dark, with two soft glows on top. Indigo top-left, green top-right
/// and a little lower, each fading out by about 70% of the screen's width.
///
/// Fills the whole screen including the safe areas, so a call site writes
/// `.background(ScreenBackground())` and nothing else.
struct ScreenBackground: View {
    var body: some View {
        GeometryReader { geo in
            let reach = geo.size.width * 0.7
            ZStack {
                Theme.backgroundGradient
                RadialGradient(
                    colors: [Brand.glowIndigo, Brand.glowIndigo.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: reach
                )
                RadialGradient(
                    colors: [Brand.glowGreen, Brand.glowGreen.opacity(0)],
                    center: UnitPoint(x: 1, y: 0.12),
                    startRadius: 0,
                    endRadius: reach
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ScreenBackground()
}
