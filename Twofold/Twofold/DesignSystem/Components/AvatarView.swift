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

    private var resolvedImage: UIImage? {
        loadedImage ?? person.avatarURL.flatMap { AvatarImageCache.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage).resizable().scaledToFill()
            } else if let avatarURL = person.avatarURL {
                placeholder
                    .task(id: avatarURL) { await load(avatarURL) }
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
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
        AvatarImageCache.shared.store(image, for: url)
        loadedImage = image
    }
}

#Preview {
    AvatarView(person: MockData.dara, size: 64, showsRing: true)
}
