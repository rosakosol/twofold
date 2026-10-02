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
            HStack(spacing: Theme.Spacing.sm) {
                Text("Drawing pad")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // A real button, not just the card's tap gesture: a gesture on a container is
                // invisible to VoiceOver and undiscoverable to everyone else.
                CircularNavButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "See both drawings side by side") {
                    fullScreen = .bothPads
                }
                // The card's primary action (section 6, Home). Opens your own pad, the same place
                // tapping your preview goes.
                Button("Draw") { showingEditor = true }
                    .buttonStyle(.twofoldPrimaryCompact)
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

    private func padPreview(title: String, url: URL?, isMine: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                if isMine {
                    showingEditor = true
                } else {
                    fullScreen = .partnerPad
                }
            } label: {
                // Paper (section 6, Home): white in light mode, a warm #E9E4DA in dark, with the
                // drawing multiplied onto it so its white background takes the paper's colour
                // instead of sitting on it as a white rectangle.
                ZStack {
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous).fill(Brand.paper)
                    CachedRemoteImage(url: url) { image in
                        image.resizable().scaledToFit().blendMode(.multiply)
                    } placeholder: {
                        if isMine { emptyPadHint }
                    }
                }
                .compositingGroup()
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .strokeBorder(Theme.line)
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
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPadHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "pencil.and.scribble")
            Text("Tap to draw").font(.caption2)
        }
        // The paper's own ink, not `textSecondary`: the paper stays light in dark mode, where the
        // adaptive token turns pale and would vanish on it.
        .foregroundStyle(Brand.paperInkSecondary)
    }

    /// Concentric with the card around it: its 26pt corners less its 16pt padding.
    private var innerRadius: CGFloat { Theme.Radius.card - Theme.Spacing.md }
}

#Preview {
    DrawingPadCard()
        .environment(AppModel())
        .padding()
        .background(Theme.backgroundGradient)
}
