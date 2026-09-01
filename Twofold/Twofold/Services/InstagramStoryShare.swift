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
//  It also requires a Facebook App ID, which is what `facebookAppID` below is for. This used to
//  omit it, on the reasoning that the attribution fields "only matter for tracking shares back to
//  a specific Facebook app ID" — that reasoning was wrong. Instagram identifies the calling app by
//  that ID and refuses the share without it, with the message users actually saw: "The app that
//  you shared doesn't currently support sharing to Stories." It isn't attribution; it's the
//  handshake.
//

import UIKit

enum InstagramStoryShare {
    /// The app's Facebook App ID, from developers.facebook.com — an app has to be registered there
    /// even though nothing else here touches Facebook, because that ID is how Instagram recognises
    /// the sender.
    ///
    /// Empty until one exists, and `isAvailable` is false while it is, so the Instagram Stories
    /// button doesn't appear at all rather than appearing and failing. Fill this in and the whole
    /// path works; nothing else needs changing.
    static let facebookAppID = ""

    private static var shareURL: URL? {
        guard !facebookAppID.isEmpty else { return nil }
        return URL(string: "instagram-stories://share?source_application=\(facebookAppID)")
    }

    /// Whether Instagram is installed *and* this build can actually complete a share — check this
    /// before showing the "Instagram Stories" button at all, rather than showing it disabled.
    ///
    /// `canOpenURL` alone was not enough: it answers "is Instagram installed", which was true, so
    /// the button showed for everyone and then failed inside Instagram for everyone.
    static var isAvailable: Bool {
        guard let shareURL else { return false }
        return UIApplication.shared.canOpenURL(shareURL)
    }

    static func shareSticker(_ image: UIImage) {
        guard let shareURL, isAvailable, let data = image.pngData() else { return }

        // Instagram's documented privacy requirement — the pasteboard payload must expire
        // shortly after being written, not linger indefinitely for any app to read later.
        let options: [UIPasteboard.OptionsKey: Any] = [.expirationDate: Date().addingTimeInterval(300)]
        let items: [String: Any] = [
            "com.instagram.sharedSticker.stickerImage": data,
            // Carried on the pasteboard as well as in the URL: Instagram has read the sender's id
            // from either depending on version, and sending both costs nothing.
            "com.instagram.sharedSticker.appID": facebookAppID,
        ]
        UIPasteboard.general.setItems([items], options: options)

        UIApplication.shared.open(shareURL)
    }
}
