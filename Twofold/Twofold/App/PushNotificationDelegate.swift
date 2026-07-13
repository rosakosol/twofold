//
//  PushNotificationDelegate.swift
//  Twofold
//
//  Registers for a device token at launch (safe/idempotent regardless of notification
//  permission status — the permission prompt itself is requested elsewhere, in
//  NotificationsSellView during onboarding). The token is posted via NotificationCenter
//  rather than reaching into AppModel directly, since a plain UIApplicationDelegate has no
//  access to the SwiftUI environment.
//
//  This makes the app capable of *receiving* a device token and uploading it
//  (AppModel.registerPushToken -> BackendService.registerDeviceToken), which is the
//  prerequisite for real push delivery — actual sending happens server-side in
//  supabase/functions/_shared/apns.ts, using separate sandbox/production APNs credentials.
//

import UIKit
import UserNotifications

extension Notification.Name {
    static let didRegisterForRemoteNotifications = Notification.Name("Twofold.didRegisterForRemoteNotifications")
    /// Posted when the user taps a delivered push notification that carries a game deep link
    /// (`sessionId`/`gameType` in its payload — see `notify-couple-event`'s `data` param). The
    /// object is a `GameNotificationDeepLink`; `RootView` observes this to open the right game.
    static let didTapGameNotification = Notification.Name("Twofold.didTapGameNotification")
}

struct GameNotificationDeepLink {
    let sessionID: UUID
    let gameType: GameType
}

final class PushNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .didRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected in the simulator, and on-device until the Apple Developer Push Notifications
        // capability + a real APNs key are configured — logged for visibility, not fatal.
        print("[push] failed to register for remote notifications: \(error.localizedDescription)")
    }

    /// Lets a push notification still show a banner/sound while the app is in the foreground —
    /// without this, iOS silently swallows it (there was no `UNUserNotificationCenterDelegate`
    /// at all before this deep-link feature needed one).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionIdString = userInfo["sessionId"] as? String,
           let sessionID = UUID(uuidString: sessionIdString),
           let gameTypeString = userInfo["gameType"] as? String,
           let gameType = GameType(rawValue: gameTypeString) {
            NotificationCenter.default.post(
                name: .didTapGameNotification, object: GameNotificationDeepLink(sessionID: sessionID, gameType: gameType)
            )
        }
        completionHandler()
    }
}
