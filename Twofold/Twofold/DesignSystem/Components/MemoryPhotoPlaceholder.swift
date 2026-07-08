//
//  MemoryPhotoPlaceholder.swift
//  Twofold
//
//  Stands in for a real photo (PhotosUI import) until memories store actual images.
//

import SwiftUI

struct MemoryPhotoPlaceholder: View {
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
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(memory.emoji)
                .font(.system(size: 32))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
