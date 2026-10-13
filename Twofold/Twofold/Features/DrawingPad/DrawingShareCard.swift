//
//  DrawingShareCard.swift
//  Twofold
//
//  Both pads on one image, to send: yours and your partner's side by side on paper, each under
//  its owner's name. The same pairing `DrawingPadPairView` shows, made into something that can
//  leave the app.
//
//  Fixed colours, rendered light (see `DrawingShareButton`): it is an image, so it looks the same
//  whatever the sender's phone is set to, and the pads themselves are drawn on white.
//

import SwiftUI

struct DrawingShareCard: View {
    let myImage: UIImage?
    let myName: String
    let partnerImage: UIImage?
    let partnerName: String
    let date: Date

    /// `ShareCardStyle.paper`'s canvas and ink, so this reads as one of the app's share cards.
    private let canvas = Color(hex: 0xFAF7F2)
    private let ink = Color(hex: 0x2A2118)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Our drawings")
                    .font(.title3.weight(.bold))
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .opacity(0.7)
            }

            HStack(alignment: .top, spacing: 14) {
                pane(image: myImage, name: myName)
                pane(image: partnerImage, name: partnerName)
            }

            HStack(spacing: 4) {
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("twofold")
                    .font(.newsreader(size: 14))
            }
            .opacity(0.8)
        }
        .foregroundStyle(ink)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(canvas)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func pane(image: UIImage?, name: String) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                // Overlaid, not stacked, for the reason `DrawingPadPairView.pane` gives: the paper
                // decides the size, so an empty pad and a drawn one come out the same height.
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().padding(6)
                    } else {
                        Text("Nothing yet")
                            .font(.caption)
                            .foregroundStyle(ink.opacity(0.5))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Loads both pads, renders the card, and offers it to the share sheet. Hidden while neither pad
/// has a drawing: a card of two empty pages is nothing to send.
struct DrawingShareButton: View {
    let myURL: URL?
    let myName: String
    let partnerURL: URL?
    let partnerName: String

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Our drawings", image: Image(uiImage: image))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share both drawings")
            }
        }
        .task(id: [myURL, partnerURL]) { await render() }
    }

    private func render() async {
        async let mine = Self.load(myURL)
        async let theirs = Self.load(partnerURL)
        let (myImage, partnerImage) = await (mine, theirs)
        guard myImage != nil || partnerImage != nil else {
            image = nil
            return
        }
        let card = DrawingShareCard(
            myImage: myImage,
            myName: myName,
            partnerImage: partnerImage,
            partnerName: partnerName,
            date: .now
        )
        // A fixed width so the image is always the same size, and an explicit light scheme because
        // the renderer otherwise ignores the phone's (see GameResultsShareView).
        let renderer = ImageRenderer(content: card.frame(width: 360).environment(\.colorScheme, .light))
        renderer.scale = displayScale
        image = renderer.uiImage
    }

    /// The disk copy first, which the screen this sits on has normally just written; the network
    /// only if it isn't there.
    private static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = RemoteImageDiskCache.image(for: url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    DrawingShareCard(myImage: nil, myName: "Dara", partnerImage: nil, partnerName: "Rosa", date: .now)
        .padding()
}
