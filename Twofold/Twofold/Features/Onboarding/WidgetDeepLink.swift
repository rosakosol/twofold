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
        case drawingPad
        case home
        case memories
        case passport

        var id: Self { self }
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == "twofold" else { return nil }
        let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
        switch url.host?.lowercased() {
        case "paywall": return .paywall
        case "flight": return id.map(Destination.flight)
        case "memory": return id.map(Destination.memory)
        case "drawing-pad": return .drawingPad
        case "home": return .home
        case "memories": return .memories
        case "passport": return .passport
        default: return nil
        }
    }
}
