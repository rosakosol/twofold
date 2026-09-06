//
//  CachedRemoteImage.swift
//  Twofold
//
//  `AsyncImage` for images that have to survive going offline.
//
//  `AsyncImage` has no useful cache here. The app's remote images are *signed* Storage URLs whose
//  token and expiry change on every re-sign, so URLSession's cache — keyed on the whole URL —
//  misses even for an image downloaded seconds earlier, and offline it has nothing to fall back on
//  at all. `RemoteImageDiskCache` keys on the storage path instead, which is stable across
//  re-signs, and keeps the bytes on disk so a cold launch with no network still draws something.
//

import SwiftUI

/// Takes an optional URL and stays in the view tree when it's nil, so callers whose URL arrives
/// after first render — as the drawing pad's signed URLs do — don't have to wrap it in an `if let`
/// and swap one view for another underneath it.
struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: UIImage?

    private var cached: UIImage? {
        loaded ?? url.flatMap { RemoteImageDiskCache.image(for: $0) }
    }

    var body: some View {
        ZStack {
            // Not decoration, and not removable: `.task` below attaches to this stack, and a view
            // that resolves to `EmptyView` has nothing in the render tree for a lifecycle modifier
            // to run against. The drawing pad's partner half passes a placeholder of
            // `if isMine { … }` — nil when it isn't yours — so before its image loaded the whole
            // view was empty, its `.task` never fired, and it could never stop being empty. The
            // user's own half, whose placeholder is a real "Tap to draw", loaded fine right next
            // to it. One point square, so it can't affect any caller's layout.
            Color.clear.frame(width: 1, height: 1)
            if let image = cached {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        // Keyed on the WHOLE url, signature included — not on the storage path.
        //
        // Path-keying was tried and is wrong, because a path is the image's *name*, not its
        // contents. Saving a drawing uploads new bytes to the same path and hands back a re-signed
        // url; keyed on the path, the id does not change, this never re-runs, and the view keeps
        // showing the image it already loaded. That is exactly what it did: the Home card stayed on
        // the old drawing while opening the pad — a fresh view with fresh state — showed the new
        // one.
        //
        // The reason path-keying was reached for is real but smaller: `loadDrawingPads()` re-signs
        // on every refresh, so this restarts and cancels an in-flight download. That is wasted
        // bandwidth, not a failure — the last task still completes, which was measured at the time.
        // Re-fetching after a re-sign is also what picks up the partner's new drawing at all.
        // Wasteful and correct beats cheap and stale.
        .task(id: url) {
            guard let url else { return }
            // The cached copy is already on screen by now, so this is a refresh rather than a
            // load — a failure leaves what's showing alone instead of blanking it.
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            RemoteImageDiskCache.store(data, for: url)
            loaded = image
        }
    }
}
