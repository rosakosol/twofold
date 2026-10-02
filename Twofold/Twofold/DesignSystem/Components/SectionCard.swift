//
//  SectionCard.swift
//  Twofold
//

import SwiftUI

/// The standard card (docs/TWOFOLD_DESIGN.md, section 5): `surface`, a 1pt `line` border, 26pt
/// corners, 16pt padding. The same in both appearances apart from the tokens themselves.
struct SectionCard<Content: View>: View {
    var content: Content
    /// For a card floating over its own busy content (the Memories map's hint): adds the floating
    /// shadow so it lifts off the map instead of sitting flush in it.
    var isFloating: Bool = false
    /// The card a screen is built around. Takes `surfaceGradient` for a touch of depth. At most one
    /// per screen.
    var isHero: Bool = false

    init(isFloating: Bool = false, isHero: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isFloating = isFloating
        self.isHero = isHero
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content
        }
        .padding(Theme.Spacing.md)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            if isHero {
                shape.fill(Theme.surfaceGradient)
            } else {
                shape.fill(Theme.surface)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        }
        .shadow(
            color: isFloating ? Theme.Shadow.color : .clear,
            radius: isFloating ? Theme.Shadow.radius : 0,
            y: isFloating ? Theme.Shadow.y : 0
        )
    }
}
