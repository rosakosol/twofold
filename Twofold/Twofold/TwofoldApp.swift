import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()
    @State private var onboardingModel = OnboardingModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WelcomeView()
            }
            .environment(appModel)
            .environment(onboardingModel)
            .preferredColorScheme(.light)
        }
    }
}
