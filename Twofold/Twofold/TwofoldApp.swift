import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RevenueCatConfig.configure()
        AnalyticsConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: .didRegisterForRemoteNotifications)) { notification in
                    guard let tokenData = notification.object as? Data else { return }
                    Task { await appModel.registerPushToken(tokenData) }
                }
                // Covers private content (game answers, photos) before the App Switcher
                // snapshot is taken — see PrivacyCoverView's own doc comment. No animation:
                // this has to win the race against the snapshot, not fade into it.
                .overlay {
                    if scenePhase != .active {
                        PrivacyCoverView().transaction { $0.animation = nil }
                    }
                }
        }
    }
}
