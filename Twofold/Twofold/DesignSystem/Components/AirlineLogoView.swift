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
    var width: CGFloat = 36
    var height: CGFloat = 18

    init(url: URL?, width: CGFloat = 36, height: CGFloat = 18) {
        self.url = url
        self.width = width
        self.height = height
    }

    /// Square convenience initializer for call sites that just want a single dimension.
    init(url: URL?, size: CGFloat) {
        self.url = url
        self.width = size
        self.height = size
    }

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()

                case .empty:
                    Color.clear

                default:
                    fallback
                }
            }
            .frame(width: width, height: height)

        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: "airplane")
            .foregroundStyle(.secondary)
            .frame(width: width, height: height)
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
