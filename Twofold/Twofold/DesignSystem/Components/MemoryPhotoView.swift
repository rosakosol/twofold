//
//  MemoryPhotoView.swift
//  Twofold
//
//  Shows the memory's uploaded photo when it has one, falling back to a gradient+emoji
//  placeholder otherwise — same fallback pattern as AvatarView.
//

import ImageIO
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
    /// Decode the photo down to roughly this many pixels on its longest side, instead of at
    /// whatever size it was uploaded. `nil` keeps the full image, which is what a screen actually
    /// showing the photo wants.
    ///
    /// Uploads are capped at 1600px (`MemoryEditingKit`), so a full decode is a ~10MB bitmap.
    /// Drawing that into a 64pt map pin means decoding about seventy times more pixels than end
    /// up on screen, and holding all of them in `MemoryPhotoImageCache` afterwards — twenty pins
    /// is some 200MB of bitmaps to draw twenty thumbnails.
    var thumbnailPixelSize: CGFloat?

    /// Only ever set by `load()` on a cache miss — a cache hit is read straight into
    /// `resolvedImage` below without waiting on this, same pattern as `AvatarView`.
    @State private var loadedImage: UIImage?

    private var primaryPhoto: MemoryPhoto? { memory.photos.first }

    private var cacheKey: String? {
        guard let photo = primaryPhoto else { return nil }
        let base = photo.path == "pending" ? photo.url.absoluteString : photo.path
        // The size belongs in the key. Without it a pin's 192px thumbnail and the detail screen's
        // full-size decode are the same entry, and whichever loads first is what the other gets —
        // either a blurry detail view or the full-size decode this exists to avoid.
        //
        // Only the *decoded* cache is keyed this way. `MemoryPhotoDiskCache` still stores the
        // original bytes under the plain path, so a thumbnail and a full decode share one download.
        guard let thumbnailPixelSize else { return base }
        return "\(base)@\(Int(thumbnailPixelSize))"
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

    /// Three tiers, cheapest first: the in-memory `NSCache`, then `MemoryPhotoDiskCache`, then the
    /// network. The disk tier is what makes memories browsable with no connection — the `NSCache`
    /// above is empty on every cold launch, and `photo.url` is a signed URL that can't be fetched
    /// offline (and has usually expired anyway), so without it a plane trip shows nothing but
    /// placeholder gradients.
    private func load(_ photo: MemoryPhoto) async {
        guard let key = cacheKey else { return }
        if let cached = MemoryPhotoImageCache.shared.image(for: key) {
            loadedImage = cached
            return
        }

        // Pending (not-yet-uploaded) photos are already real local files courtesy of
        // `PendingMemoryStore`, so there's nothing to cache a second copy of.
        let isUploaded = photo.path != "pending"

        if isUploaded, let data = MemoryPhotoDiskCache.read(path: photo.path), let image = await decoded(data) {
            MemoryPhotoImageCache.shared.store(image, for: key)
            loadedImage = image
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: photo.url), let image = await decoded(data) else { return }
        if isUploaded { MemoryPhotoDiskCache.write(data, path: photo.path) }
        MemoryPhotoImageCache.shared.store(image, for: key)
        loadedImage = image
    }

    /// Decodes off the main actor, at `thumbnailPixelSize` when one is set.
    ///
    /// The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `load()` — and therefore
    /// the `UIImage(data:)` that used to sit in it — runs on the main actor. On a cold launch with
    /// an empty `NSCache` that is a full-size JPEG decode per visible pin, on the thread drawing
    /// the map.
    private func decoded(_ data: Data) async -> UIImage? {
        let target = thumbnailPixelSize
        return await Task.detached(priority: .userInitiated) {
            guard let target else { return UIImage(data: data) }
            return MemoryPhotoView.downsampled(data, maxPixelSize: target)
        }.value
    }

    /// `nonisolated` deliberately: without it this inherits MainActor isolation and the detached
    /// task above would hop straight back to the main thread to do the work.
    nonisolated static func downsampled(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Decode now, on this thread. Otherwise the work is merely deferred to first draw,
            // which is the main thread again.
            kCGImageSourceShouldCacheImmediately: true,
            // Honour EXIF orientation, which `UIImage(data:)` did for us.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // A file the decoder cannot read at all — fall back rather than show nothing.
            return UIImage(data: data)
        }
        return UIImage(cgImage: thumbnail)
    }
}
