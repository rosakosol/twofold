//
//  MemoryPhotoView.swift
//  Twofold
//
//  Shows the memory's uploaded photo when it has one, falling back to a gradient+emoji
//  placeholder otherwise — same fallback pattern as AvatarView.
//

import SwiftUI

/// In-memory only, keyed by the photo's stable storage `path` rather than its signed `url` — the
/// `memory-photos` bucket is private, so `url` is re-resolved (and therefore a *different*
/// string) on every `fetchCoupleState()` reload, which would make a plain url-keyed cache miss on
/// every fresh data load, not just app relaunch. Keying on `path` means a `MemoryPhotoView` that
/// scrolls off/on screen — or a whole new data fetch — still resolves from cache instead of
/// re-downloading. Not-yet-synced local photos share the literal path `"pending"` (see
/// `PendingMemoryStore`), so those fall back to keying on `url` instead to avoid one pending
/// memory's image colliding with another's in the cache. Internal (not `private`) so other views
/// that render an already-uploaded `MemoryPhoto` outside `MemoryPhotoView` itself — e.g.
/// `AddMemoryView`'s existing-photo thumbnails — can share the same cache instead of each
/// re-downloading independently.
@MainActor
final class MemoryPhotoImageCache {
    static let shared = MemoryPhotoImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

struct MemoryPhotoView: View {
    let memory: Memory
    var cornerRadius: CGFloat = 16

    /// Only ever set by `load()` on a cache miss — a cache hit is read straight into
    /// `resolvedImage` below without waiting on this, same pattern as `AvatarView`.
    @State private var loadedImage: UIImage?

    private var primaryPhoto: MemoryPhoto? { memory.photos.first }

    private var cacheKey: String? {
        guard let photo = primaryPhoto else { return nil }
        return photo.path == "pending" ? photo.url.absoluteString : photo.path
    }

    private var resolvedImage: UIImage? {
        loadedImage ?? cacheKey.flatMap { MemoryPhotoImageCache.shared.image(for: $0) }
    }

    private var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [Theme.skyBlue, Theme.leafGreen],
            [Theme.heartRed, .orange],
            [.purple, Theme.skyBlue],
            [Theme.leafGreen, .yellow],
        ]
        return palettes[memory.photoSeed % palettes.count]
    }

    var body: some View {
        // `scaledToFill()` deliberately overflows whatever size is proposed to it (to preserve
        // aspect ratio while covering the frame), and `.clipShape` masks against a view's actual
        // rendered size, not the size a caller's external `.frame()` requests — so without this
        // GeometryReader pinning the image to the real available size *before* clipShape runs,
        // a non-square source photo bleeds outside the intended thumbnail bounds.
        GeometryReader { geo in
            Group {
                if let resolvedImage {
                    Image(uiImage: resolvedImage).resizable().scaledToFill()
                } else if let primaryPhoto {
                    placeholder
                        .task(id: cacheKey) { await load(primaryPhoto) }
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // `loadedImage` otherwise outlives a change in which photo is actually primary — e.g.
        // this row's memory has its first photo removed, leaving a different one as
        // `photos.first` — since this view's own identity (keyed by the stable `memory.id` in
        // list/map rows) doesn't change and `resolvedImage` prefers the stale cached
        // `loadedImage` over re-deriving from the new `cacheKey`. Clearing it here lets
        // `resolvedImage` fall through to a fresh cache lookup (instant if already cached) or
        // the placeholder+load path (if not) for the photo that's actually primary now.
        .onChange(of: cacheKey) { loadedImage = nil }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func load(_ photo: MemoryPhoto) async {
        guard let key = cacheKey else { return }
        if let cached = MemoryPhotoImageCache.shared.image(for: key) {
            loadedImage = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: photo.url), let image = UIImage(data: data) else { return }
        MemoryPhotoImageCache.shared.store(image, for: key)
        loadedImage = image
    }
}
