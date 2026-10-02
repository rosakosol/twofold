//
//  AvatarPair.swift
//  Twofold
//

import SwiftUI

/// The two of you (docs/TWOFOLD_DESIGN.md, section 5): two photos with a 2pt white ring and a
/// coral filled heart between them. VoiceOver reads it as one element, "Alex and Sam".
///
/// Solo (no partner yet) it shows just the one face, and no heart: a heart beside one person
/// reads as a placeholder for someone missing.
struct AvatarPair: View {
    let me: Person
    let partner: Person?
    var size: CGFloat = 44
    /// On a coloured gradient a bare coral heart can all but disappear (about 1.3:1 on blue), so
    /// there it sits on a small white disc: still coral, still the two of you, but visible.
    var isOnColour: Bool = false

    var body: some View {
        HStack(spacing: size * 0.16) {
            AvatarView(person: me, size: size, showsRing: true)
            if let partner {
                if isOnColour {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.26, weight: .bold))
                        .foregroundStyle(Theme.coralFill)
                        .frame(width: size * 0.5, height: size * 0.5)
                        .background(.white, in: Circle())
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(Theme.coral)
                }
                AvatarView(person: partner, size: size, showsRing: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(partner.map { "\(me.name) and \($0.name)" } ?? me.name)
    }
}

#Preview {
    AvatarPair(me: MockData.rosa, partner: MockData.dara)
        .padding()
        .background(Theme.backgroundGradient)
}
