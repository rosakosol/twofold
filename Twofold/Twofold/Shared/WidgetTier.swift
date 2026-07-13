//
//  WidgetTier.swift
//  Twofold
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj). Mirrors AppModel.isDeckLocked's exact tier comparison so
//  widgets gate Plus/Premium content the same way Games does — no second tiering concept.
//

import Foundation

enum WidgetTier {
    static let plus = "plus"
    static let premium = "premium"

    static func isLocked(required: String, current: String?) -> Bool {
        required == premium && current != premium
    }

    static func lockCaption(required: String) -> String {
        required == premium ? "Twofold Premium" : "Twofold Plus"
    }
}
