//
//  DrawingPadFullScreenView.swift
//  Twofold
//
//  Read-only full-screen viewer for a partner's drawing pad — DrawingPadEditorView is
//  edit-and-save only and always targets "your" pad, so it isn't reusable here as-is.
//

import PostHog
import SwiftUI

struct DrawingPadFullScreenView: View {
    let title: String
    let url: URL?
    /// The navigation title, when the possessive form built below isn't the right one. Defaults to
    /// nil, which keeps "<name>'s pad" — correct for the partner's pad, which is what this screen
    /// was built for and still its usual caller. `DrawingPadPairView` also opens *your* pad from
    /// here, where that same composition would read "You's pad".
    var screenTitle: String?
    /// Whose pad this is, for the share sheet's card and stickers. No share button without one.
    var owner: Person? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    /// The fetch's answer; nil while it is on its way.
    @State private var result: DrawingPadLoadResult?

    /// What the screen shows.
    enum Content {
        case loading
        case drawing(UIImage)
        case nothingDrawn
        /// There may be a drawing and it could not be fetched: an error with Try again, never
        /// "Nothing drawn yet".
        case failed
    }

    /// `cached` is the disk copy, shown while the fetch is still out so the drawing the card
    /// showed appears at once.
    static func content(for result: DrawingPadLoadResult?, cached: UIImage?) -> Content {
        switch result {
        case nil: cached.map(Content.drawing) ?? .loading
        case let .loaded(image): .drawing(image)
        case .blank: .nothingDrawn
        case .failed: .failed
        }
    }

    private var cached: UIImage? { url.flatMap { RemoteImageDiskCache.image(for: $0) } }

    private func load() async {
        result = await DrawingPadLoader.load(url)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                switch Self.content(for: result, cached: cached) {
                case let .drawing(image):
                    // Matches `DrawingPadEditorView`'s canvas treatment (white card, rounded
                    // corners, soft shadow) — the read-only viewer had been showing the same
                    // image full-bleed with no card framing at all.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .themedShadow(Theme.Shadow.paper)
                        .padding(Theme.Spacing.lg)
                case .nothingDrawn:
                    EmptyStateView(systemImage: "pencil.and.scribble", title: "Nothing drawn yet")
                case .failed:
                    ErrorStateView(title: "Couldn't load this drawing", message: "Check your connection and try again.") {
                        await load()
                    }
                case .loading:
                    ProgressView()
                }
            }
            // Through `DrawingPadLoader`, not `AsyncImage` (HOME-10). The URL is signed, so
            // `AsyncImage` missed on every re-sign and had nothing at all offline — and it showed
            // any failure as "Nothing drawn yet", so a pad the Home card had just drawn could open
            // here claiming to be empty. The loader tells "nothing there" (a 404) from "couldn't
            // fetch it", and falls back to the disk copy the card itself draws from.
            .task(id: url) { await load() }
            .navigationTitle(screenTitle ?? "\(title)'s pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if owner != nil, url != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { sharing = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share drawing")
                    }
                }
            }
        }
        .sheet(isPresented: $sharing) {
            if let owner {
                DrawingShareSheet(pads: [.init(person: owner, url: url)])
            }
        }
        .postHogScreenView("Drawing Pad: Partner View")
    }
}

#Preview {
    DrawingPadFullScreenView(title: "Ewin", url: nil)
        .environment(AppModel())
}
