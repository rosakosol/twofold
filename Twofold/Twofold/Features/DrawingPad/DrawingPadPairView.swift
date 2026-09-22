//
//  DrawingPadPairView.swift
//  Twofold
//
//  Both pads at once, side by side — the comparison the card itself can only hint at, with two
//  120pt previews sat next to the title.
//
//  Draws through `CachedRemoteImage` rather than `AsyncImage` for exactly the reason
//  `DrawingPadCard` documents: the pads are signed Storage URLs, so URLSession's cache (which keys
//  on the whole URL) misses every time one is re-signed, and offline it has nothing at all. This
//  screen is reached by tapping the card, so it is opened in precisely the state where the card's
//  own images are already cached and a second, uncached loader would show two blank rectangles
//  next to two visible ones.
//

import PostHog
import SwiftUI

struct DrawingPadPairView: View {
    let myURL: URL?
    let partnerName: String
    let partnerURL: URL?

    /// Width-to-height of each pane. Deliberately *not* the canvas's own ~3:5: at half the screen
    /// each, two panes of that shape are tall thin columns, which is the thing this shape exists to
    /// avoid. 3:4 reads as a picture rather than a strip, and leaves the gradient visible above and
    /// below the pair instead of running them the full height of the screen.
    private let paneAspectRatio: CGFloat = 3.0 / 4.0

    @Environment(\.dismiss) private var dismiss

    /// Tapping a pane opens that drawing on its own. Side by side on a phone gives each one less
    /// than half the screen's width, which is enough to compare the two and not always enough to
    /// actually look at one — so the comparison is what this screen opens as, and the close-up is
    /// one tap further in rather than a thing you have to back out to the card to reach.
    @State private var focused: FocusedPad?

    private struct FocusedPad: Identifiable {
        let id = UUID()
        /// The name under the pane ("You", or the partner's name).
        let name: String
        /// The close-up screen's own title. Carried rather than composed from `name`, because the
        /// possessive form that is right for a partner ("Sam's pad") is wrong for your own.
        let screenTitle: String
        let url: URL?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    pane(name: "You", screenTitle: "Your pad", url: myURL)
                    pane(name: partnerName, screenTitle: "\(partnerName)'s pad", url: partnerURL)
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Your drawings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $focused) { pad in
            DrawingPadFullScreenView(title: pad.name, url: pad.url, screenTitle: pad.screenTitle)
        }
        .postHogScreenView("Drawing Pad: Both")
    }

    private func pane(name: String, screenTitle: String, url: URL?) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                focused = FocusedPad(name: name, screenTitle: screenTitle, url: url)
            } label: {
                // The paper, and the only thing in this pane allowed to decide how big it is.
                //
                // The image hangs off it as an overlay rather than sharing a `ZStack` with it, and
                // that is the whole fix for a real bug: the two pads came out different heights
                // whenever one person had drawn and the other had not.
                //
                // `scaledToFill` does not merely paint outside its box, it *reports* a size that
                // covers the proposal. Offered a 3:4 pane, a canvas that is roughly 3:5 answers
                // with something nearer 1:1.67 — and a `ZStack` sizes itself to the largest child,
                // so that taller answer became the pane, `aspectRatio` having already done its work
                // one level up. The empty pane had no such child (the placeholder is a small fixed
                // `VStack`) so it stayed honestly 3:4, and the pair sat side by side with a visible
                // step between them.
                //
                // An overlay is sized *by* its parent and cannot push back, so the ratio holds
                // whatever the image reports, and `clipShape` below crops what spills.
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.white)
                    // Cropping gives up the top and bottom of each drawing in exchange for a pane
                    // you can read at a glance, which is the trade this screen wants — it exists to
                    // put the two next to each other, and the whole drawing is one tap away on the
                    // pane itself.
                    .aspectRatio(paneAspectRatio, contentMode: .fit)
                    .overlay {
                        CachedRemoteImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            emptyState
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.subtleInk.opacity(0.15))
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name)'s drawing")
            .accessibilityHint("Opens this drawing on its own")

            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "pencil.and.scribble")
                .font(.title2)
            Text("Nothing yet")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.subtleInk)
    }
}

#Preview {
    DrawingPadPairView(myURL: nil, partnerName: "Ewin", partnerURL: nil)
        .environment(AppModel())
}
