//
//  NotificationRouteTests.swift
//  TwofoldTests
//
//  Every push the backend sends, parsed the way `PushNotificationDelegate` parses a real tap.
//  The payloads below are copied from what each Edge Function actually puts on the wire — the
//  point of these tests is that the two halves agree, since a mismatch between them is silent:
//  the notification still arrives and still opens the app, it just lands nowhere in particular.
//

import Testing
import Foundation
@testable import Twofold

struct NotificationRouteTests {

    /// APNs custom keys sit at the top level alongside `aps` (see `_shared/apns.ts`), which is the
    /// shape `UNNotificationContent.userInfo` hands back — so these mirror that, `aps` included.
    private func userInfo(_ custom: [String: Any]) -> [AnyHashable: Any] {
        var payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "T", "body": "B"], "sound": "default"]]
        for (key, value) in custom { payload[key] = value }
        return payload
    }

    // MARK: - What each backend sender produces

    /// `notify-couple-event`, for game_reminder / game_results_ready / game_partner_finished.
    @Test func gamePushOpensThatSession() {
        let sessionID = UUID()
        let route = NotificationRoute(userInfo: userInfo([
            "sessionId": sessionID.uuidString,
            "gameType": GameType.thisOrThat.rawValue,
            "eventType": "game_results_ready",
        ]))
        #expect(route == .game(sessionID: sessionID, gameType: .thisOrThat))
    }

    /// `_shared/notify.ts` — departure/arrival/delay pushes, all three of which used to send no
    /// identifier at all despite having the flight id in scope.
    @Test func flightPushOpensThatFlight() {
        let flightID = UUID()
        let route = NotificationRoute(userInfo: userInfo(["flightId": flightID.uuidString]))
        #expect(route == .flight(flightID))
    }

    /// `send-streak-reminders`, both the early nudge and the "1 hour left" one.
    @Test func streakReminderOpensTheDailyQuestion() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "daily_question"])) == .dailyQuestion)
    }

    /// `send-partner-invite-reminders`.
    @Test func inviteReminderOpensTheInviteFlow() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "invite_partner"])) == .invitePartner)
    }

    /// `notify-couple-event`'s drawing_saved *self* branch — "your new drawing was saved", which
    /// is about your own pad, so it opens the editor.
    @Test func ownDrawingConfirmationOpensYourEditor() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "drawing_pad"])) == .drawingPad)
    }

    /// The partner branch of the same event. Both used to send `drawing_pad`, so tapping
    /// "<partner> saved a new drawing" opened your own blank canvas instead of the drawing you had
    /// just been told about — the notification named a thing and then didn't show it to you.
    @Test func partnerDrawingPushOpensTheirPad() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "partner_drawing_pad"])) == .partnerDrawingPad)
    }

    /// The two are genuinely different destinations, not aliases — this is the whole fix.
    @Test func theTwoDrawingRoutesAreNotTheSame() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "drawing_pad"]))
            != NotificationRoute(userInfo: userInfo(["route": "partner_drawing_pad"])))
    }

    /// The widget's own URLs land on the same pair, so a tap on the small Drawing Pad widget —
    /// which shows only the partner's drawing — opens the partner's drawing too.
    @Test func widgetDrawingURLsMatchTheirNotificationRoutes() {
        #expect(WidgetDeepLink.destination(for: URL(string: "twofold://drawing-pad")!) == .drawingPad)
        #expect(WidgetDeepLink.destination(for: URL(string: "twofold://partner-drawing-pad")!) == .partnerDrawingPad)
    }

    // MARK: - Nothing to route on

    /// A bare alert with no custom keys must parse to nil rather than to some default screen —
    /// yanking someone somewhere they didn't ask to go is worse than leaving them where they were.
    @Test func plainAlertHasNoRoute() {
        #expect(NotificationRoute(userInfo: userInfo([:])) == nil)
    }

    @Test func unknownRouteNameIsIgnoredRatherThanGuessed() {
        #expect(NotificationRoute(userInfo: userInfo(["route": "something_we_dont_ship_yet"])) == nil)
    }

    // MARK: - Malformed payloads

    /// A truncated or corrupted id must not resolve to a route — routing on a nil/garbage id would
    /// open an empty screen, which reads as the app being broken rather than the push being.
    @Test func malformedIdentifiersProduceNoRoute() {
        #expect(NotificationRoute(userInfo: userInfo(["flightId": "not-a-uuid"])) == nil)
        #expect(NotificationRoute(userInfo: userInfo([
            "sessionId": "not-a-uuid", "gameType": GameType.triviaBattle.rawValue,
        ])) == nil)
    }

    /// A game type this build doesn't know (an older app receiving a newer push) is not a game
    /// route — better to open the app plainly than to force-unwrap something unrecognised.
    @Test func unknownGameTypeProducesNoRoute() {
        #expect(NotificationRoute(userInfo: userInfo([
            "sessionId": UUID().uuidString, "gameType": "quantum_charades",
        ])) == nil)
    }

    /// Half a game payload is not a game route.
    @Test func gameIdWithoutTypeProducesNoRoute() {
        #expect(NotificationRoute(userInfo: userInfo(["sessionId": UUID().uuidString])) == nil)
    }

    // MARK: - Router behaviour

    /// The whole reason `NotificationRouter` exists: a tap that arrives before there's any UI to
    /// receive it has to still be there when the UI shows up. The old `NotificationCenter.post`
    /// was dropped outright when nothing was subscribed.
    @MainActor
    @Test func routerHoldsTheRouteUntilSomethingTakesIt() {
        let router = NotificationRouter.shared
        router.pending = nil

        let flightID = UUID()
        router.route(from: userInfo(["flightId": flightID.uuidString]))
        #expect(router.pending == .flight(flightID))
        // Still there on a second read — a reader that wasn't ready must not consume it.
        #expect(router.pending == .flight(flightID))

        router.pending = nil
        #expect(router.pending == nil)
    }

    /// An unroutable push must not clear a route that's already waiting — otherwise a plain
    /// notification arriving in the same batch would quietly cancel the one that mattered.
    @MainActor
    @Test func unroutablePushLeavesAnExistingRouteAlone() {
        let router = NotificationRouter.shared
        let flightID = UUID()
        router.pending = .flight(flightID)

        router.route(from: userInfo([:]))

        #expect(router.pending == .flight(flightID))
        router.pending = nil
    }
}
