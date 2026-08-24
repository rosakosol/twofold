//
//  NotificationRoute.swift
//  Twofold
//
//  Where a tapped push notification should land. Parsing is kept here, pure and free of UIKit,
//  so it's directly unit-testable (see TwofoldTests/NotificationRouteTests.swift) — the delegate
//  that receives the tap only has to turn `userInfo` into one of these and hand it over.
//
//  `NotificationRouter` is the other half: a tap can arrive long before there's any UI to receive
//  it, so the route is *held* rather than broadcast. See its own doc comment.
//

import Foundation
import Observation

/// Every destination a notification can point at. Deliberately mirrors `WidgetDeepLink.Destination`
/// where the two overlap (a flight, the drawing pad) — the app already knows how to open those, so
/// notifications route into the same screens rather than growing a parallel set.
enum NotificationRoute: Hashable {
    case game(sessionID: UUID, gameType: GameType)
    /// The daily question. No session id travels in the payload: the reminder is scheduled per
    /// person from a cron, well before anyone has opened (and therefore created) that day's
    /// session, so the app resolves it on arrival instead.
    case dailyQuestion
    case flight(UUID)
    case drawingPad
    /// "Your partner still hasn't joined" — lands on the invite flow rather than the app's root.
    case invitePartner

    /// Custom APNs keys ride at the top level of the payload alongside `aps`, which is where
    /// `UNNotificationContent.userInfo` surfaces them.
    ///
    /// `sessionId`/`gameType` are matched first and kept in their original spelling: those keys
    /// have been going out in game pushes since before this type existed, and notifications
    /// already sitting in Notification Center when the app updates still carry the old shape.
    init?(userInfo: [AnyHashable: Any]) {
        if let sessionIDString = userInfo["sessionId"] as? String,
           let sessionID = UUID(uuidString: sessionIDString),
           let gameTypeString = userInfo["gameType"] as? String,
           let gameType = GameType(rawValue: gameTypeString) {
            self = .game(sessionID: sessionID, gameType: gameType)
            return
        }

        if let flightIDString = userInfo["flightId"] as? String,
           let flightID = UUID(uuidString: flightIDString) {
            self = .flight(flightID)
            return
        }

        switch userInfo["route"] as? String {
        case "daily_question": self = .dailyQuestion
        case "drawing_pad": self = .drawingPad
        case "invite_partner": self = .invitePartner
        default: return nil
        }
    }
}

/// Holds the route from a tapped notification until there is somewhere to put it.
///
/// The previous approach posted a `NotificationCenter` message from the tap handler and had
/// `RootView` observe it. That only works if `RootView` is already on screen and listening —
/// which is exactly what isn't true in the common case. Tapping a notification for an app that
/// isn't running delivers the tap during launch, before any SwiftUI view exists to subscribe, and
/// `NotificationCenter` has no buffering: with no subscriber the message is simply gone. The deep
/// link was reliably lost precisely when it mattered most.
///
/// Holding it instead makes arrival order irrelevant. `RootView` drains it when it's ready, and
/// "ready" means more than mounted — see `consumePendingRoute()` there.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    /// Non-nil while a tapped notification is waiting to be acted on. Cleared only by whoever
    /// actually opens the destination, never by a reader that wasn't ready for it yet.
    var pending: NotificationRoute?

    private init() {
        #if DEBUG
        // Seeds a route at launch from `-notificationRoute <value>`, so the cold-launch path — a
        // tap arriving before any UI exists, which is the case that was broken — can be exercised
        // without a backend or a real APNs delivery. Values match the wire format:
        // `daily_question`, `drawing_pad`, `invite_partner`, or `flight:<uuid>`.
        // Used by AppWalkthroughUITests; DEBUG-only, so it cannot exist in a shipped build.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-notificationRoute"), flag + 1 < arguments.count {
            let value = arguments[flag + 1]
            if value.hasPrefix("flight:"), let id = UUID(uuidString: String(value.dropFirst("flight:".count))) {
                pending = .flight(id)
            } else {
                pending = NotificationRoute(userInfo: ["route": value])
            }
        }
        #endif
    }

    func route(from userInfo: [AnyHashable: Any]) {
        guard let route = NotificationRoute(userInfo: userInfo) else { return }
        pending = route
    }
}
