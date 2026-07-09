import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                // Theme's palette (card backgrounds, ink colors, gradients) is all fixed-light,
                // not dark-mode-adaptive, so letting the system switch to dark mode makes card
                // text unreadable (dark ink on a dark system card background).
                .preferredColorScheme(.light)
        }
    }
}
