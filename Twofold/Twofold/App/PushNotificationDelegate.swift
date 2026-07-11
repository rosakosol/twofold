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
//  prerequisite for real push delivery — actually sending one still requires the
//  APNS_KEY_ID/APNS_TEAM_ID/APNS_AUTH_KEY/APNS_BUNDLE_ID secrets to be set server-side (see
//  supabase/functions/_shared/apns.ts, which safely no-ops until then).
//

import UIKit

extension Notification.Name {
    static let didRegisterForRemoteNotifications = Notification.Name("Twofold.didRegisterForRemoteNotifications")
}

final class PushNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
}
