//
//  DrawingPadCard.swift
//  Twofold
//
//  Draws through `CachedRemoteImage` rather than `AsyncImage`: the pads are signed Storage URLs, so
//  `AsyncImage` (and URLSession's own cache, which keys on the whole URL) misses every time the URL
//  is re-signed, and offline it has nothing at all — a cold launch on a plane showed two blank
//  rectangles where the couple's drawings should be.
//

import SwiftUI

struct DrawingPadCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingEditor = false

    /// One `item`-based cover for both destinations rather than a `isPresented` cover each. Two
    /// `fullScreenCover`s attached to the same view is the kind of thing that works until it
    /// quietly doesn't — only one presentation of a given kind per view is reliable — and an enum
    /// also makes "which of these can be open" a single piece of state instead of two booleans
    /// that can both be true.
    @State private var fullScreen: FullScreenDestination?

    private enum FullScreenDestination: Identifiable {
        /// The partner's pad on its own — tapping their preview.
        case partnerPad
        /// Both pads side by side — tapping the card itself.
        case bothPads

        var id: Self { self }
    }

    var body: some View {
        SectionCard {
            HStack {
                Text("Drawing pad")
                    .font(.headline)
                Spacer()
                // A real button, not just the card's tap gesture: a gesture on a container is
                // invisible to VoiceOver and undiscoverable to everyone else, and this card has
                // spent its life with two tappable previews and an inert background.
                Button { fullScreen = .bothPads } label: { expandBadge }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See both drawings side by side")
            }
            HStack(spacing: Theme.Spacing.md) {
                padPreview(title: "You", url: appModel.myDrawingURL, isMine: true)
                padPreview(title: appModel.partner.name, url: appModel.partnerDrawingURL, isMine: false)
            }
        }
        // Anywhere on the card that isn't one of the two previews. The previews are `Button`s, so
        // they take their own taps first and keep going where they always went — editing yours,
        // opening theirs — which is the distinction being asked for here: the pod expands, the
        // pads do what pads do.
        .contentShape(Rectangle())
        .onTapGesture { fullScreen = .bothPads }
        .sheet(isPresented: $showingEditor) {
            DrawingPadEditorView()
        }
        .fullScreenCover(item: $fullScreen) { destination in
            switch destination {
            case .partnerPad:
                DrawingPadFullScreenView(title: appModel.partner.name, url: appModel.partnerDrawingURL)
            case .bothPads:
                DrawingPadPairView(
                    myURL: appModel.myDrawingURL,
                    partnerName: appModel.partner.name,
                    partnerURL: appModel.partnerDrawingURL
                )
            }
        }
        .task { await appModel.loadDrawingPads() }
    }

    private var expandBadge: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.subtleInk)
            .padding(Theme.Spacing.sm)
            .background(Theme.subtleInk.opacity(0.1), in: Circle())
    }

    private func padPreview(title: String, url: URL?, isMine: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                if isMine {
                    showingEditor = true
                } else {
                    fullScreen = .partnerPad
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                    CachedRemoteImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        if isMine { emptyPadHint }
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.subtleInk.opacity(0.15))
                )
            }
            // No `.disabled(!isMine)` here anymore — that was the actual cause of the partner's
            // pad looking "transparent/muted": SwiftUI dims a disabled Button's label by default,
            // which reads exactly like a rendering/opacity bug even though nothing about the
            // image itself was ever altered. Both previews are tappable now, just to different
            // destinations (edit vs. view full screen).
            .buttonStyle(.plain)

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPadHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "pencil.and.scribble")
            Text("Tap to draw").font(.caption2)
        }
        .foregroundStyle(Theme.subtleInk)
    }
}

#Preview {
    DrawingPadCard()
        .environment(AppModel())
        .padding()
        .background(Theme.backgroundGradient)
}
