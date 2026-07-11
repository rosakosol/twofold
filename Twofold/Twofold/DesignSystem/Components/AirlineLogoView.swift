//
//  AirlineLogoView.swift
//  Twofold
//
//  Small circular airline tailfin logo, loaded from a public logo CDN keyed by IATA code (see
//  AirlineLogo.swift) — falls back to a generic airplane glyph when there's no code to derive a
//  URL from, or the image fails to load, rather than leaving an empty gap.
//

import SwiftUI

struct AirlineLogoView: View {
    let url: URL?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Theme.cardBackground, in: Circle())
        .overlay(Circle().strokeBorder(Theme.subtleInk.opacity(0.12), lineWidth: 1))
        .clipShape(Circle())
    }

    private var fallback: some View {
        Image(systemName: "airplane")
            .font(.system(size: size * 0.42))
            .foregroundStyle(Theme.subtleInk)
    }
}

#Preview {
    HStack {
        AirlineLogoView(url: AirlineLogo.url(forIATACode: "QF"))
        AirlineLogoView(url: AirlineLogo.url(forIATACode: "SQ"), size: 36)
        AirlineLogoView(url: nil)
    }
    .padding()
}
