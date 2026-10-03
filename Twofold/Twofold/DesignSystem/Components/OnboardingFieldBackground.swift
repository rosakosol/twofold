//
//  OnboardingFieldBackground.swift
//  Twofold
//
//  Shared text-field/secure-field chrome for onboarding's account/name/code entry screens —
//  previously each of the 9 screens with a text input inlined its own identical
//  `.background(Theme.surface, in: RoundedRectangle(...))` with no border at all. That
//  was tolerable in light mode (the field's fill still read as distinct from the page), but
//  against dark mode's now-deep `Theme.backgroundGradient`, an unbordered dark-gray field became
//  nearly invisible. One shared modifier means the fix (and any future one) lands everywhere at
//  once instead of needing to be repeated 14 times across 9 files.
//

import SwiftUI

/// A single-line field on the redesign's terms (section 5): a capsule on `surface` with a 1pt
/// `controlLine` outline. The outline is what marks the field, so it is the control-outline token
/// (3.5:1 / 3.4:1), not the decorative `line` a card uses.
///
/// Drawn as a rounded rectangle with half the standard field's height as its radius, so a field
/// at the usual 54pt is exactly a capsule. A `Capsule` itself would round the ends of a field
/// that has grown at the largest text sizes into a tall oval that cuts into its text.
private struct OnboardingFieldBackground: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 27, style: .continuous)

    func body(content: Content) -> some View {
        // No `.padding()` here: every call site applies its own immediately before this modifier.
        content
            .background(Theme.surface, in: shape)
            .overlay {
                shape.strokeBorder(Theme.controlLine, lineWidth: 1)
            }
    }
}

extension View {
    func onboardingFieldBackground() -> some View {
        modifier(OnboardingFieldBackground())
    }
}
