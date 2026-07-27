//
//  PersonInitialBadge.swift
//  LiveActivities
//
//  DistanceWidget's big non-overlapping pair either side of a heart. (DistanceCompactWidget uses
//  CoupleHeartInitials instead — both initials together inside one heart, not separate circles.)
//  Accessory Lock Screen widgets render in a single system-applied tint (`.accessory` widget
//  rendering mode ignores custom colors), so this reads as an outline + letter rather than
//  anything resembling the real colored AvatarView circles elsewhere in the app.
//

import SwiftUI

func personInitial(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
}

struct PersonInitialBadge: View {
    let letter: String
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: size >= 24 ? 1.5 : 1)
            Text(letter).font(.system(size: size * 0.5, weight: .bold))
        }
        .frame(width: size, height: size)
    }
}
