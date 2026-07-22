//
//  PrivacyCoverView.swift
//  Twofold
//
//  Shown full-screen the instant the app leaves `.active` (backgrounding, app switcher, an
//  incoming call/Control Center swipe) and removed the instant it returns — otherwise the last
//  frame on screen (a partner's private game answer, a photo, a memory) is exactly what iOS
//  snapshots for the App Switcher and exactly what a screen recording/shoulder-surf would catch
//  mid-transition. No animation on either edge: appearing has to beat the snapshot, and
//  disappearing has to not leave a flash of real content half-covered.
//

import SwiftUI

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient
            TwofoldBrandMark()
        }
        .ignoresSafeArea()
    }
}

#Preview {
    PrivacyCoverView()
}
