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

    var body: some View {
        HStack(spacing: size * 0.16) {
            AvatarView(person: me, size: size, showsRing: true)
            if let partner {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Theme.coral)
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
