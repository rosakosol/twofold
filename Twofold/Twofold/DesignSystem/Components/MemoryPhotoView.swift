//
//  MemoryPhotoView.swift
//  Twofold
//
//  Shows the memory's uploaded photo when it has one, falling back to a gradient+emoji
//  placeholder otherwise — same fallback pattern as AvatarView.
//

import SwiftUI

struct MemoryPhotoView: View {
    let memory: Memory
    var cornerRadius: CGFloat = 16

    private var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [Theme.skyBlue, Theme.leafGreen],
            [Theme.heartRed, .orange],
            [.purple, Theme.skyBlue],
            [Theme.leafGreen, .yellow],
        ]
        return palettes[memory.photoSeed % palettes.count]
    }

    var body: some View {
        Group {
            if let photoURL = memory.photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
