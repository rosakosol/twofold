//
//  WidgetDeepLink.swift
//  Twofold
//
//  Tap targets for every Home Screen/Lock Screen widget — a locked widget always points at
//  `twofold://paywall`; an unlocked one points at whatever it's actually showing (a specific
//  flight, a specific memory, the drawing pad, or a tab). Kept separate from InviteCode.swift's
//  link parsing (a different URL shape/purpose), mirroring its "just build/parse the URL" scope.
//

import Foundation

enum WidgetDeepLink {
    /// `Identifiable` (id = itself) so RootView can drive a `fullScreenCover(item:)` directly
    /// off it for the non-tab destinations (flight/memory/drawingPad).
    enum Destination: Hashable, Identifiable {
        case paywall
        case flight(UUID)
        case memory(UUID)
        /// A specific trip's detail screen — where the Trip Countdown widget lands, rather than on
        /// the Home tab it used to.
        case trip(UUID)
        case drawingPad
        /// Read-only view of the partner's pad. Where the small Drawing Pad widget — which shows
        /// only their drawing — and the "<partner> saved a new drawing" push both land.
        case partnerDrawingPad
        case home
        case memories
        /// The Stats tab, optionally on a named card. Days Together is about the relationship, so
        /// it asks for that one by name instead of landing on whichever card was last open.
        case passport(StatsSection?)

        var id: Self { self }
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == "twofold" else { return nil }
        let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
        switch url.host?.lowercased() {
        case "paywall": return .paywall
        case "flight": return id.map(Destination.flight)
        case "memory": return id.map(Destination.memory)
        case "trip": return id.map(Destination.trip)
        case "drawing-pad": return .drawingPad
        case "partner-drawing-pad": return .partnerDrawingPad
        case "home": return .home
        case "memories": return .memories
        // `twofold://passport` for the tab, `twofold://passport/relationship` for a named card.
        case "passport":
            // Matched case-insensitively: `StatsSection`'s raw values are the *display* strings
            // ("Relationship"), and a URL path shouldn't have to carry their capitalisation.
            let name = url.pathComponents.dropFirst().first?.lowercased()
            let section = StatsSection.allCases.first { $0.rawValue.lowercased() == name }
            return .passport(section)
        default: return nil
        }
    }
}
