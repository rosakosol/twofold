//
//  CardAppearance.swift
//  Twofold
//
//  How a card arrives and leaves.
//
//  Home's cards are driven by state that resolves a round trip after the screen is already on
//  screen — whether there is a subscription, whether a partner exists, whether there are any trips.
//  Gating each on "do we know yet" stops them asserting the wrong thing, but it does not stop them
//  snapping in and out the moment the answer lands, which reads as the layout glitching.
//
//  So they grow and fade instead. The height change is the important half: a card appearing above
//  others shoves everything down, and an instant shove is what makes it feel broken rather than
//  alive.
//
//  `.animation(_:value:)` on the value, not a bare `withAnimation`, because these changes arrive
//  from network callbacks scattered across `AppModel` rather than from anything a person tapped —
//  there is no single call site to wrap.
//

import SwiftUI

extension AnyTransition {
    /// Fade in while growing very slightly; fade out on the way back.
    ///
    /// The height change does not come from here. Inserting into an animated stack animates the
    /// layout by itself, and that reflow is what the eye actually reads as the card making room for
    /// itself — the scale only stops the content appearing at full size inside a box that is still
    /// growing, which looks like a jump however smooth the reflow is.
    ///
    /// `.top` anchor so it grows downward from where it will sit rather than outward from its own
    /// middle. 0.96 rather than something dramatic: this is a card settling into a list, not an
    /// entrance.
    ///
    /// Asymmetric because leaving and arriving are not the same event. A card that has gone has
    /// already been read and does not need announcing; one arriving is new information, and the
    /// half-beat of growth is what gives the eye time to notice it.
    static var card: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

/// One duration for every card, so a screen where two resolve at once settles as a single movement
/// rather than two overlapping ones.
enum CardMotion {
    static let appearance: Animation = .snappy(duration: 0.28)
}
