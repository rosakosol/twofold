//
//  AppLockEnabledConfirmationView.swift
//  Twofold
//
//  Shown once, right after `SettingsView`'s app-lock toggle successfully authenticates and turns
//  the lock on — confirms the setup actually took rather than leaving the user to infer it from
//  the toggle's own position. Same GlobeHeart-adjacent visual language as `AppLockView` (the
//  screen this same feature shows on every subsequent locked launch), just with a checkmark
//  standing in for the lock glyph.
//

import SwiftUI

struct AppLockEnabledConfirmationView: View {
    let methodName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.leafGreen.opacity(0.18))
                        .frame(width: 116, height: 116)
                        .blur(radius: 16)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Theme.leafGreen)
                }

                Text("\(methodName) Enabled")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            Text("Twofold will now ask for \(methodName) whenever you reopen the app.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

#Preview {
    AppLockEnabledConfirmationView(methodName: "Face ID")
}
