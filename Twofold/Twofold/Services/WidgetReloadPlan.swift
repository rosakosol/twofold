//
//  WidgetReloadPlan.swift
//  Twofold
//
//  Which widget timelines to reload after the app writes a new snapshot. Main-app-only: the
//  widgets never reload themselves this way.
//

import Foundation
import WidgetKit

/// The images the app caches for the widgets in the app group (see `WidgetImageCache`). The
/// widgets read them at render time, so a new image only shows once its widgets reload.
enum WidgetImage: Hashable {
    case myAvatar
    case partnerAvatar
    case airlineLogo
    case latestMemory
}

enum WidgetReloadPlan {
    /// The kinds whose timelines should reload, going from `old` to `new` with `changedImages`
    /// rewritten, plus `forced`.
    static func kinds(
        from old: WidgetSnapshot?,
        to new: WidgetSnapshot,
        changedImages: Set<WidgetImage> = [],
        forced: Set<WidgetKind> = []
    ) -> Set<WidgetKind> {
        Set(WidgetKind.allCases)
    }

    /// Hands `kinds` to WidgetKit, and nothing when there are none.
    static func reload(_ kinds: Set<WidgetKind>) {
        guard !kinds.isEmpty else { return }
        if kinds == Set(WidgetKind.allCases) {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }
}
