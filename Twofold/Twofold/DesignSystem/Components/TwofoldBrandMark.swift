//
//  TwofoldBrandMark.swift
//  Twofold
//
//  Shared brand header (GlobeHeart + "twofold" wordmark) used everywhere the app generates
//  a shareable image — the Passport card, the Snapshot theme cards, and the individual Full
//  Flight Stats cards — so every exported image reads as the same product.
//

import SwiftUI

struct TwofoldBrandMark: View {
    var color: Color = Theme.ink
    var size: CGFloat = 32
    var textStyle: Font.TextStyle = .title2

    var body: some View {
        VStack(spacing: 4) {
            Image("GlobeHeart")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            Text("twofold")
                .font(.system(textStyle, design: .serif))
                .foregroundStyle(color)
        }
    }
}

#Preview {
    TwofoldBrandMark()
}
