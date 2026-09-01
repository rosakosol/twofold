//
//  AppLockConfirmationView.swift
//  Twofold
//
//  Shown right after `SettingsView`'s app-lock toggle successfully authenticates — in *both*
//  directions. Turning the lock on confirmed itself; turning it off said nothing at all, leaving
//  the one change that removes a protection as the only one you had to infer from a switch's
//  position. Both directions now say what happened.
//
//  Same GlobeHeart-adjacent visual language as `AppLockView` (the screen this feature shows on
//  every subsequent locked launch), with the glyph and colour carrying which way it went.
//

import SwiftUI

struct AppLockConfirmationView: View {
    /// `Identifiable` so `SettingsView` can drive the sheet off `sheet(item:)` — the value itself
    /// is the identity, since there are only ever two and they're mutually exclusive.
    enum Change: Identifiable {
        case enabled
        case disabled

        var id: Self { self }
    }

    let change: Change
    let methodName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var symbol: String {
        switch change {
        case .enabled: "checkmark.circle.fill"
        case .disabled: "lock.open.fill"
        }
    }

    /// Green for the protection going on. Deliberately not red for it going off — turning it off
    /// is a thing the user just chose to do, not a failure or a warning at them; `subtleInk` states
    /// it without scolding.
    private var accent: Color {
        switch change {
        case .enabled: Theme.leafGreen
        case .disabled: Theme.subtleInk
        }
    }

    private var title: String {
        switch change {
        case .enabled: "\(methodName) Enabled"
        case .disabled: "\(methodName) Turned Off"
        }
    }

    private var detail: String {
        switch change {
        case .enabled: "Twofold will now ask for \(methodName) whenever you reopen the app."
        case .disabled: "Twofold won't ask for \(methodName) anymore. Anyone with your phone can open it."
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 116, height: 116)
                        .blur(radius: 16)
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    // The fix for the reported truncation. This is presented at a fixed detent
                    // height with flexible space above and below, and a `Text` squeezed by that
                    // truncates rather than growing — which is how a two-line sentence became
                    // "Twofold will now ask for Face ID…". `fixedSize` makes the text's own
                    // natural height win, so it wraps and the spacers give way instead.
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: Theme.Spacing.lg)

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
        // The detents live here rather than at the call site because the decision depends on the
        // text size, which is only in scope inside the sheet's own content. Half a screen fits the
        // message comfortably at ordinary sizes; at accessibility sizes the same message runs to
        // three or four lines and pushes "Done" off the bottom of a `.medium` sheet, so it opens
        // full-height instead. Both are always offered — this only chooses which one it starts at.
        .presentationDetents(
            [.medium, .large],
            selection: .constant(dynamicTypeSize.isAccessibilitySize ? .large : .medium)
        )
    }
}

#Preview("Enabled") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AppLockConfirmationView(change: .enabled, methodName: "Face ID")
            .presentationDetents([.medium, .large])
    }
}

#Preview("Disabled") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AppLockConfirmationView(change: .disabled, methodName: "Face ID")
            .presentationDetents([.medium, .large])
    }
}
