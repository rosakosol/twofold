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
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    /// Keyed on the URL's path alone, not the full URL — `avatarURL` is a *signed* URL
    /// (`BackendService.avatarSignedURL`), and per that function's own doc comment "each signed
    /// URL embeds its own unique token/expiry, so it's never the same string twice." Caching by
    /// the full URL therefore missed on every single couple-state refresh (every screen
    /// navigation that re-fetches it), even for a photo already downloaded seconds earlier —
    /// exactly what read as the avatar flickering back to its placeholder while navigating
    /// around the app. The storage path itself is stable across re-signs, so that's the real
    /// cache key.
    private func cacheKey(for url: URL) -> NSString { url.path as NSString }

    func image(for url: URL) -> UIImage? { cache.object(forKey: cacheKey(for: url)) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: cacheKey(for: url)) }
}

extension AvatarView {
    /// Called right after a successful avatar upload (`AppModel.updateAvatar`/
    /// `updatePartnerAvatar`) — re-uploading overwrites the same deterministic storage path (see
    /// `BackendService.uploadAvatar`'s doc comment), and the cache above is now keyed on that
    /// same stable path (not the fresh signed URL) so navigating around the app doesn't keep
    /// re-fetching an already-downloaded photo. Without this, that same path-keyed cache would
    /// otherwise keep serving the *previous* photo under this path until some `AvatarView`
    /// happened to load the new signed URL fresh from the network.
    @MainActor
    static func preloadCache(imageData: Data, url: URL) {
        guard let image = UIImage(data: imageData) else { return }
        AvatarImageCache.shared.store(image, for: url)
    }
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
        // Without this VoiceOver reads the placeholder's initials literally — "P" — which tells
        // nobody anything, and the accessibility audit flags those initials as unscalable text.
        // They genuinely can't scale: the circle is a fixed diameter because it doubles as a map
        // pin, a share-card element and an overlapping-stack chip. Naming the person here is the
        // right fix for both — the identity is carried by the label rather than by 12pt of text.
        // A caller that needs to say more (e.g. "Ada, finished") can still override this label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.name)
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

    /// How far the accent is blended toward black for the placeholder fill. White initials on the
    /// raw accent measured 2.60:1 against `skyBlue` and 3.40:1 against `heartRed` in light mode,
    /// and 1.70:1 / 2.01:1 in dark mode — well under WCAG AA's 4.5:1, on the small avatars (size
    /// 30–32, so ~12pt initials) that appear on every tab. This is Theme.swift's own stated rule
    /// applied here: "only the deepened tone is licensed" wherever white content sits on a fill.
    ///
    /// Deepening decisively rather than a little is deliberate. Blending ~20% lands every accent in
    /// the mid-luminance valley where *neither* white nor dark ink clears 4.5:1 (measured: the
    /// worst case gets worse, not better). Going darker keeps one text colour — white — uniform
    /// across light and dark rather than flipping per person.
    ///
    /// These numbers are calibrated against rendered pixels, not arithmetic: `mix(in: .device)`
    /// interpolates in linear light, so it darkens noticeably harder than the same fraction would
    /// in sRGB components. Sampling the real screenshot puts the two live accents at 7.4:1
    /// (heartRed) and 6.0:1 (skyBlue) — comfortably past AA's 4.5:1 with the accent still clearly
    /// itself, where the arithmetic-derived 0.45 came out closer to 10:1 and read as near-black.
    /// Sampled fills: `#8F3942` (7.42:1) and `#31698B` (5.96:1), against 3.40:1 and 2.60:1 before.
    private static let fillDeepening = 0.30
    private static let fillDeepeningEnd = 0.45

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            person.accentColor.mix(with: .black, by: Self.fillDeepening, in: .device),
                            person.accentColor.mix(with: .black, by: Self.fillDeepeningEnd, in: .device),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(person.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                // Explicitly hidden as well as covered by the container's
                // `.accessibilityElement(children: .ignore)` below. That modifier alone wasn't
                // enough everywhere: where a caller wraps the avatar in its own overlay or button
                // (DailyActivityCard, DeckCardRow), the initials came back as their own ~7x12pt
                // static-text elements. The name on the container is the label; this glyph is
                // decoration.
                .accessibilityHidden(true)
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
