//
//  MemoryMapPin.swift
//  Twofold
//
//  A memory on a map: a small square print of its photo, framed the way the memory detail screen
//  frames the same picture — white border, slight tilt — with a count badge where a place holds
//  more than one.
//
//  Shared by the real Memories map and onboarding's mock of it, because those two had already
//  drifted. The real one grew from a 44pt circle into this; onboarding's kept drawing the circle,
//  so the screen selling the feature showed something the app no longer did. One view means the
//  next change to either lands on both by construction.
//
//  The photo is a closure rather than a `Memory`, which is the only real difference between the two
//  call sites: the app has an uploaded photo to load, and onboarding has a bundled illustration.
//

import SwiftUI

struct MemoryMapPin<Photo: View>: View {
    /// How many memories are at this place. The badge appears from two upward.
    let count: Int
    @ViewBuilder var photo: () -> Photo

    /// Big enough to make out what the photo is of. The 44pt circle it replaced was a map marker
    /// rather than a picture — too small to tell one memory from another, and cropped to a shape
    /// that fights the rectangle every photo actually is.
    private static var photoSize: CGFloat { 64 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            photo()
                .frame(width: Self.photoSize, height: Self.photoSize)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                // Tilted like the detail screen's print, a touch further: two degrees reads as a
                // rendering mistake at this size, where four reads as deliberate.
                .rotationEffect(.degrees(-4))

            if count > 1 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.heartRed, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -6)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        MemoryMapPin(count: 1) { Color.gray }
        MemoryMapPin(count: 4) { Color.gray }
    }
    .padding(40)
}
