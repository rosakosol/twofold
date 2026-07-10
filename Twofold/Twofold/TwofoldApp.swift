import SwiftUI

@main
struct TwofoldApp: App {
    @State private var pairedAppModel: AppModel = {
        let m = AppModel()
        m.couple.partnerA.name = "Rosa"
        m.couple.partnerA.homeCity = Place.commonCities[0]
        m.couple.partnerB.name = "Bug" // a nickname, distinct from their real name
        m.couple.partnerB.homeCity = Place.commonCities[4]
        m.couple.startedDatingOn = Calendar.current.date(byAdding: .day, value: -134, to: .now) ?? .now
        m.partnerConnected = true
        return m
    }()

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environment(pairedAppModel)
                .preferredColorScheme(.light)
        }
    }
}
