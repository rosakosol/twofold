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
                // Device-local override (Settings → Appearance) — `nil` for the default
                // "System" choice, which `.preferredColorScheme` already treats as "follow the
                // system setting," so this is a no-op until someone actually picks Light/Dark.
                .preferredColorScheme(AppearancePreference.current.colorScheme)
                // …and on the window itself, which is what carries the override into sheets. See
                // `AppearancePreference.applyToWindows`. Run on appear as well as on change, since
                // a window exists to be styled only once the scene is up.
                .onAppear { AppearancePreference.applyToWindows() }
                .onChange(of: AppearancePreference.current) { _, _ in
                    AppearancePreference.applyToWindows()
                }
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
