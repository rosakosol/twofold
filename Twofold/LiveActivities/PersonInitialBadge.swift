//
//  PersonInitialBadge.swift
//  LiveActivities
//
//  Shared by DistanceWidget and DistanceCompactWidget's two different initial-circle treatments
//  (big + heart vs. small + overlapping) — same badge, just a different size/arrangement, rather
//  than two hand-rolled copies. Accessory Lock Screen widgets render in a single system-applied
//  tint (`.accessory` widget rendering mode ignores custom colors), so this reads as an outline +
//  letter rather than anything resembling the real colored AvatarView circles elsewhere in the app.
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
