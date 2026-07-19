//
//  OnboardingMemoryAssets.swift
//  Twofold
//
//  Real bundled photos for the mock `Memory` values `MemoriesSellView`/`MapSellView` build —
//  `sunset`/`trip`/`where-we-met` in Assets.xcassets, matching those mocks' own titles ("That
//  sunset", "First trip together", "Where we met") and `photoSeed` ordering 1:1. Standing in for
//  `MemoryPhotoView`'s real-photo-loaded look (same `GeometryReader`+`.clipped()`+corner-radius
//  clip shape) rather than its gradient+`photo.fill` placeholder, since these mocks have no real
//  uploaded photo to load.
//

import SwiftUI

enum OnboardingMemoryAssets {
    /// Indexed by `Memory.photoSeed` (0, 1, 2) — the same seed both sell screens already use.
    static let imageNames = ["sunset", "trip", "where-we-met"]

    static func imageName(forSeed seed: Int) -> String {
        imageNames[seed % imageNames.count]
    }
}

struct OnboardingMemoryImage: View {
    let seed: Int
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            Image(OnboardingMemoryAssets.imageName(forSeed: seed))
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
