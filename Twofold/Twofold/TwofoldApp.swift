import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) private var pushDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: .didRegisterForRemoteNotifications)) { notification in
                    guard let tokenData = notification.object as? Data else { return }
                    Task { await appModel.registerPushToken(tokenData) }
                }
        }
    }
}
