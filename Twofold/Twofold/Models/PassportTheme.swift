//
//  PassportTheme.swift
//  Twofold
//
//  Shared palette for everything styled like the actual travel document — the Passport card on
//  the Stats tab and its full-page share card (`PassportShareCard`). Navy cover, gold foil, cream
//  paper — deliberately its own look (not `Theme`'s sky-blue/leaf-green app palette) since these
//  are styled to read as the real document their name promises, not another app screen.
//

import SwiftUI

enum PassportTheme {
    static let coverTop = Color(hex: "1B2A4A")
    static let coverBottom = Color(hex: "0B111F")
    static let gold = Color(hex: "D8B463")
    static let cream = Color(hex: "F3ECD9")
}

/// The ICAO biometric-passport cover symbol — a small rounded outline with a chip/aperture
/// circle at its center, printed on the front of every real e-passport. Stands in for the
/// generic seal/emblem icon a placeholder passport card would otherwise use.
struct BiometricPassportSymbol: View {
    var color: Color = PassportTheme.gold
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .stroke(color, lineWidth: max(1, size * 0.09))
                .frame(width: size, height: size * 0.7)
            Circle()
                .stroke(color, lineWidth: max(1, size * 0.07))
                .frame(width: size * 0.32, height: size * 0.32)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    BiometricPassportSymbol(size: 60)
        .padding()
        .background(PassportTheme.coverBottom)
}
