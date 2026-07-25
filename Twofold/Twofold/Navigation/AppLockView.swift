//
//  AppLockView.swift
//  Twofold
//
//  The full-screen cover `RootView` shows in front of everything else (including its own
//  loading spinner) while `AppLockService.isLocked` is true — same GlobeHeart + wordmark
//  language as `BrandLoadingView`, so a locked launch still feels like Twofold and not a bare
//  system prompt, with a lock glyph standing in for the loading spinner's pulse.
//

import SwiftUI

struct AppLockView: View {
    let appLock: AppLockService
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Theme.skyBlue.opacity(0.18))
                            .frame(width: 116, height: 116)
                            .blur(radius: 16)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(Theme.skyBlue)
                    }

                    Text("twofold")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(Theme.ink)
                }

                Text("Unlock to continue")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)

                Spacer()

                Button {
                    authenticate()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: appLock.methodName == "Passcode" ? "lock.fill" : "faceid")
                        Text("Unlock with \(appLock.methodName)")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        // Auto-prompts immediately so the common case (device already has Face ID/Touch ID) never
        // needs the manual button below — that's only the fallback for a dismissed/failed prompt.
        .onAppear { authenticate() }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            await appLock.authenticate()
            isAuthenticating = false
        }
    }
}

#Preview {
    AppLockView(appLock: AppLockService())
}
