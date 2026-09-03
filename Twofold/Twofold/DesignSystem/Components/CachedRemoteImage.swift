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

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = loaded ?? RemoteImageDiskCache.image(for: url) {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            // The cached copy is already on screen by now, so this is a refresh rather than a
            // load — a failure leaves what's showing alone instead of blanking it.
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            RemoteImageDiskCache.store(data, for: url)
            loaded = image
        }
    }
}
