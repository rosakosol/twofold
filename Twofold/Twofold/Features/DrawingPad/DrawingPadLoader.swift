//
//  DrawingPadLoader.swift
//  Twofold
//
//  What the editor starts from: the pad as saved, nothing at all, or "couldn't tell".
//
//  The third answer is the one that matters. The editor used to fetch with a bare `try?` and treat
//  every failure as an empty pad, so offline, on an expired signed URL or on a flaky network it
//  opened blank, and Save then uploaded just the new strokes over the drawing it had failed to
//  show — for the partner too, who sees the same object. A failure is now its own result, and the
//  editor asks before letting a save replace a drawing it never loaded.
//

import UIKit

enum DrawingPadLoadResult {
    /// No drawing was ever saved: the URL has nothing behind it, or there is no URL.
    case blank
    case loaded(UIImage)
    /// There may be a drawing, and it could not be fetched or decoded.
    case failed
}

enum DrawingPadLoader {
    typealias Fetch = (URL) async throws -> (Data, URLResponse)

    /// The network first, then the disk copy.
    ///
    /// Network first, not the cache first the read-only screens use: this is the image a save
    /// writes on top of, so it should be the newest one there is — the same account on a second
    /// device may have saved since this one cached. The disk copy is the fallback, which is exactly
    /// the offline and flaky-network case that used to come up blank.
    ///
    /// A 404 is the one failure that means "nothing there". The pad's URL is signed whether or not
    /// anything was ever uploaded to it (see `BackendService.drawingPadSignedURL`), so a person who
    /// has never drawn gets a URL that 404s, and must be able to save their first drawing without
    /// being warned they're about to replace one.
    static func load(
        _ url: URL?,
        fetch: Fetch = { try await URLSession.shared.data(from: $0) },
        cached: (URL) -> UIImage? = RemoteImageDiskCache.image(for:),
        store: (Data, URL) -> Void = RemoteImageDiskCache.store
    ) async -> DrawingPadLoadResult {
        guard let url else { return .blank }
        do {
            let (data, response) = try await fetch(url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 { return .blank }
            if (200..<300).contains(status), let image = UIImage(data: data) {
                store(data, url)
                return .loaded(image)
            }
        } catch {
            // Falls through to the disk copy.
        }
        if let image = cached(url) { return .loaded(image) }
        return .failed
    }
}
