//
//  AvatarView.swift
//  Twofold
//

import SwiftUI

/// In-memory only (no disk tier — avatars are small and re-fetch cheaply on a cold launch) so
/// repeated `AvatarView` remounts of the same person (e.g. a game round's `.id()` reset tearing
/// down and rebuilding the whole round subtree every turn) can resolve synchronously instead of
/// flashing back to the placeholder each time.
@MainActor
private final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() {}

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Shows the person's uploaded photo when they have one, falling back to an
/// initials-on-gradient placeholder otherwise.
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 44
    var showsRing: Bool = false

    /// Only ever set by `load()` on a cache miss — a cache hit is read straight into `resolvedImage`
    /// below without waiting on this, so a view that remounts after the image is already cached
    /// (see the file doc comment) renders the real photo on its very first pass, no placeholder frame.
    @State private var loadedImage: UIImage?
    /// The URL `loadedImage` was actually loaded for — without tracking this alongside the image,
    /// `resolvedImage` kept preferring a stale `loadedImage` forever once set once, even after
    /// `person.avatarURL` changed (e.g. right after uploading a new avatar): the `.task(id:)` that
    /// re-fetches only ran from the placeholder branch, which became permanently unreachable the
    /// moment any image had ever loaded. That's what made a changed avatar look like it "didn't
    /// save" — it saved fine, every already-mounted AvatarView just never re-rendered it.
    @State private var loadedURL: URL?

    private var resolvedImage: UIImage? {
        if let loadedImage, loadedURL == person.avatarURL { return loadedImage }
        return person.avatarURL.flatMap { AvatarImageCache.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsRing {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        // Keyed on the URL itself (not just presence of one) — re-runs whenever
        // `person.avatarURL` changes to a different value, including right after a re-upload
        // produces a fresh cache-busted URL, instead of only firing on the very first load.
        .task(id: person.avatarURL) {
            guard let avatarURL = person.avatarURL else {
                loadedImage = nil
                loadedURL = nil
                return
            }
            await load(avatarURL)
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [person.accentColor, person.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(person.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func load(_ url: URL) async {
        if let cached = AvatarImageCache.shared.image(for: url) {
            loadedImage = cached
            loadedURL = url
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
        AvatarImageCache.shared.store(image, for: url)
        loadedImage = image
        loadedURL = url
    }
}

#Preview {
    AvatarView(person: MockData.dara, size: 64, showsRing: true)
}
