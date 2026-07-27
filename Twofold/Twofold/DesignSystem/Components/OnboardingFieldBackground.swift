//
//  OnboardingFieldBackground.swift
//  Twofold
//
//  Shared text-field/secure-field chrome for onboarding's account/name/code entry screens —
//  previously each of the 9 screens with a text input inlined its own identical
//  `.background(Theme.cardBackground, in: RoundedRectangle(...))` with no border at all. That
//  was tolerable in light mode (the field's fill still read as distinct from the page), but
//  against dark mode's now-deep `Theme.backgroundGradient`, an unbordered dark-gray field became
//  nearly invisible. One shared modifier means the fix (and any future one) lands everywhere at
//  once instead of needing to be repeated 14 times across 9 files.
//

import SwiftUI

private struct OnboardingFieldBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // No `.padding()` here — every call site already applies its own immediately before
        // this modifier, so adding a second one here would double it up.
        content
            // Same dark-mode treatment as `SectionCard`: a translucent `Theme.cardGradientDark`
            // wash lifts the field a shade brighter than the page instead of relying on a
            // hairline border to separate it. Light mode keeps the plain fill + border.
            .background {
                ZStack {
                    Theme.cardBackground
                    if colorScheme == .dark {
                        Theme.cardGradientDark
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                if colorScheme != .dark {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.subtleInk.opacity(0.25), lineWidth: 1.25)
                }
            }
    }
}

extension View {
    func onboardingFieldBackground() -> some View {
        modifier(OnboardingFieldBackground())
    }
}
