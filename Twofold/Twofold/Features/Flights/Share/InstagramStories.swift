//
//  InstagramStories.swift
//  Twofold
//
//  Meta's "Sharing to Stories" hand-off: the sticker goes on the pasteboard as a PNG with a top and
//  bottom background colour, and `instagram-stories://share` opens Instagram's story composer
//  with it. Meta requires the app's Meta (Facebook) App ID as `source_application`; it is read from
//  the `MetaAppID` key in Info.plist, and without one the hand-off is simply not offered.
//

import UIKit

enum InstagramStories {
    private static var appID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "MetaAppID") as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return id
    }

    private static func shareURL(_ appID: String) -> URL? {
        URL(string: "instagram-stories://share?source_application=\(appID)")
    }

    /// True when there is an App ID and Instagram is installed. `canOpenURL` needs
    /// `instagram-stories` in `LSApplicationQueriesSchemes`, which Info.plist lists.
    @MainActor
    static var isAvailable: Bool {
        guard let appID, let url = shareURL(appID) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Hands the sticker to Instagram. The pasteboard item expires after five minutes, so it doesn't
    /// linger for whatever is pasted next.
    @MainActor
    static func share(sticker: UIImage, topColor: String, bottomColor: String) async -> Bool {
        guard let appID, let url = shareURL(appID), let png = sticker.pngData() else { return false }
        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.stickerImage": png,
                "com.instagram.sharedSticker.backgroundTopColor": topColor,
                "com.instagram.sharedSticker.backgroundBottomColor": bottomColor,
            ]],
            options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)]
        )
        return await UIApplication.shared.open(url)
    }
}
