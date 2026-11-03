//
//  ImageMemoryCache.swift
//  Twofold
//
//  The decoded images the app keeps in memory: one `NSCache` per kind of image, behind one type.
//
//  Avatars, memory photos and airline logos each had a cache class of their own, three copies of
//  the same dozen lines. What genuinely differs between them is the key — a signed URL's storage
//  path for avatars, a path plus a decode size for photos, the whole URL for public logos — and
//  that stays with each caller, which knows why its key is what it is. The disk tiers stay separate
//  too (`RemoteImageDiskCache`, `MemoryPhotoDiskCache`), because they are sized and evicted
//  differently on purpose.
//

import UIKit

@MainActor
final class ImageMemoryCache {
    /// Avatars, keyed on the signed URL's storage path (see `AvatarView`).
    static let avatars = ImageMemoryCache()
    /// Memory photos, keyed on storage path and decode size (see `MemoryPhotoView.cacheKey`).
    static let memoryPhotos = ImageMemoryCache()
    /// Airline logos, keyed on their public URL (see `AirlineLogoView`).
    static let airlineLogos = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}
