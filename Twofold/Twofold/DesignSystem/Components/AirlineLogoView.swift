//
//  AirlineLogoView.swift
//  Twofold
//
//  Small circular airline tailfin logo, loaded from a public logo CDN keyed by IATA code (see
//  AirlineLogo.swift) — falls back to a generic airplane glyph when there's no code to derive a
//  URL from, or the image fails to load, rather than leaving an empty gap.
//

import SwiftUI

/// In-memory only, same reasoning as `AvatarView`'s own cache — a List row's `AirlineLogoView`
/// gets torn down and rebuilt as it scrolls off/on screen, and `AsyncImage` alone has no
/// persistent cache across that, so every scroll re-fetched the same logo from the network and
/// flashed back to the fallback glyph in between. Unlike avatars, these are plain public CDN
/// URLs (never re-signed), so the full URL is already a stable cache key — no path-only keying
/// needed here.
@MainActor
private final class AirlineLogoCache {
    static let shared = AirlineLogoCache()
    private let cache = NSCache<NSURL, UIImage>()
    /// In-flight fetches keyed by URL — a list full of the same airline (the common case: most
    /// couples fly the same 1-2 carriers repeatedly) scrolling into view for the first time in a
    /// session used to fire one independent network request per row for the *identical* URL, so
    /// whichever ones didn't win the race still sat on the fallback glyph until their own request
    /// happened to finish. Sharing one in-flight `Task` per URL means every row asking for the
    /// same logo at once resolves together, the moment the single real fetch completes.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private init() {}

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }

    /// Fetches (or joins an already-running fetch for) `url`, caching a success before returning.
    /// Never throws — a failure just resolves to `nil` for every awaiter.
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
                return nil
            }
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { store(image, for: url) }
        return image
    }
}

struct AirlineLogoView: View {
    let url: URL?
    var width: CGFloat = 36
    var height: CGFloat = 18

    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?
    /// True once a load for the current `url` has failed — distinct from `loadedImage == nil`
    /// (which is also true before a load has even started) so the fallback glyph shows
    /// immediately on a known failure instead of waiting on a retry that isn't coming.
    @State private var failedURL: URL?

    init(url: URL?, width: CGFloat = 36, height: CGFloat = 18) {
        self.url = url
        self.width = width
        self.height = height
    }

    /// Square convenience initializer for call sites that just want a single dimension.
    init(url: URL?, size: CGFloat) {
        self.url = url
        self.width = size
        self.height = size
    }

    private var resolvedImage: UIImage? {
        if let loadedImage, loadedURL == url { return loadedImage }
        return url.flatMap { AirlineLogoCache.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage)
                    .resizable()
                    // `.scaledToFit()` let the CDN logo's own square canvas letterbox inside
                    // whatever frame a call site sized it to, reading as excess padding around a
                    // tiny mark — filling (and cropping the negligible overflow) makes the logo
                    // actually fill the space it's given.
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .task(id: url) {
            guard let url, url != failedURL else { return }
            await load(url)
        }
    }

    private var fallback: some View {
        Image(systemName: "airplane")
            .foregroundStyle(.secondary)
            .frame(width: width, height: height)
    }

    private func load(_ url: URL) async {
        guard let image = await AirlineLogoCache.shared.load(url) else {
            failedURL = url
            return
        }
        loadedImage = image
        loadedURL = url
    }
}

#Preview {
    HStack {
        AirlineLogoView(url: AirlineLogo.url(forIATACode: "QF"))
        AirlineLogoView(url: AirlineLogo.url(forIATACode: "SQ"), size: 36)
        AirlineLogoView(url: nil)
    }
    .padding()
}
