import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RevenueCatConfig.configure()
        AnalyticsConfig.configure()
        // Reclassifies what earlier versions already wrote. Setting a protection class on a write
        // does nothing to files that exist, so without this the change only ever helps new
        // installs. Cheap after the first run — one `UserDefaults` read — and it defers itself if
        // the device is locked.
        DataProtectionMigration.runIfNeeded()
    }

    var body: some Scene {
        // One window only: Info.plist sets `UIApplicationSupportsMultipleScenes` to false. That
        // needs `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO` on this target, or
        // Xcode's generated manifest replaces the plist's and turns multiple scenes back on.
        //
        // iPhone Duo turns multiple scenes on by default, and this app is not built for two
        // windows. `RootView` keeps the app lock, the subscription store and the launch pipeline
        // as per-window `@State`, all running against this one `AppModel`. A second window would
        // run session restore twice, lock independently of the first, and race it for a
        // notification route. Split View beside another app is unaffected.
        WindowGroup {
            RootView()
                .environment(appModel)
                // Device-local override (Settings → Appearance), applied to the window rather than
                // through `.preferredColorScheme`.
                //
                // That modifier used to be here as well, and was the thing keeping Settings light.
                // It writes the scheme into the environment, and a sheet inherits the environment
                // it was presented with — so picking Light baked light into the open Settings
                // sheet, and going back to System passed `nil`, which is "no preference" rather
                // than "clear the preference". Measured: with both in place, switching back to
                // System left the window resolving to dark and the sheet's own hosting controller
                // still resolving to light, even after its override was explicitly cleared.
                //
                // The window override alone carries into every presentation, so this is one
                // mechanism instead of two that disagree. Run on appear as well as on change,
                // since a window exists to be styled only once the scene is up.
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
