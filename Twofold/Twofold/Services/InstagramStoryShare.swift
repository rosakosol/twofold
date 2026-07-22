//
//  InstagramStoryShare.swift
//  Twofold
//
//  Instagram's documented third-party "share to Stories" mechanism — not a standard share sheet
//  action, so it's its own helper rather than something `ShareLink` covers. Requires
//  `instagram-stories` registered under `LSApplicationQueriesSchemes` in Info.plist (iOS blocks
//  `canOpenURL` for any scheme not pre-declared there). Shares as a *sticker* (not a full-bleed
//  background) so the rendered card lands on Instagram's own composer as a movable/resizable
//  sticker over whatever the user picks as their story background — matches how every reference
//  screenshot's card looks like a small pass/map rather than a full-screen image.
//

import UIKit

enum InstagramStoryShare {
    private static let shareURL = URL(string: "instagram-stories://share")!

    /// Whether Instagram is installed and able to receive a Stories share — check this before
    /// showing the "Instagram Stories" button at all, rather than showing it disabled.
    static var isAvailable: Bool {
        UIApplication.shared.canOpenURL(shareURL)
    }

    /// Facebook's app-attribution fields are intentionally omitted — those only matter for
    /// tracking shares back to a specific Facebook app ID, which this app doesn't have
    /// registered; Instagram accepts a sticker-only payload without them.
    static func shareSticker(_ image: UIImage) {
        guard isAvailable, let data = image.pngData() else { return }

        // Instagram's documented privacy requirement — the pasteboard payload must expire
        // shortly after being written, not linger indefinitely for any app to read later.
        let options: [UIPasteboard.OptionsKey: Any] = [.expirationDate: Date().addingTimeInterval(300)]
        let items: [String: Any] = ["com.instagram.sharedSticker.stickerImage": data]
        UIPasteboard.general.setItems([items], options: options)

        UIApplication.shared.open(shareURL)
    }
}
