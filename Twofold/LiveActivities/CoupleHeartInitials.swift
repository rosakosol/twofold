//
//  CoupleHeartInitials.swift
//  LiveActivities
//
//  DistanceCompactWidget's alternative to two separate initial circles — both initials sitting
//  together inside one heart outline instead. An *outline* heart (`"heart"`, not `"heart.fill"`)
//  specifically: accessory Lock Screen widgets render everything in one system-applied tint
//  (`.accessory` rendering mode ignores custom colors), so a *filled* heart would render the
//  same color as the text on top of it, making the initials invisible. An outline leaves the
//  interior transparent, the same trick PersonInitialBadge's circle already relies on.
//

import SwiftUI

struct CoupleHeartInitials: View {
    let myInitial: String
    let partnerInitial: String
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Image(systemName: "heart")
                .font(.system(size: size, weight: .regular))
            HStack(spacing: 1) {
                Text(myInitial)
                Text(partnerInitial)
            }
            .font(.system(size: size * 0.32, weight: .bold))
            // Nudged down slightly — a heart glyph's widest, roundest area sits just below the
            // cleft between its two top lobes, not at the shape's true vertical center.
            .offset(y: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}
