//
//  FlightInfoCard.swift
//  Twofold
//
//  Flight Details' aircraft type and registration. Premium-only.
//

import SwiftUI

struct FlightInfoCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight
    let onLocked: (PremiumFlightFeature) -> Void

    @ViewBuilder
    var body: some View {
        if flight.aircraftType != nil || flight.registration != nil {
            if appModel.subscription.isPremiumLocked {
                FlightPremiumLockedCard(feature: .flightInfo) { onLocked(.flightInfo) }
            } else {
                SectionCard {
                    Text("Flight information").font(.subheadline.weight(.semibold))
                    FlightDetailRow(label: "Aircraft", value: flight.aircraftType ?? "Not available")
                    FlightDetailRow(label: "Registration", value: flight.registration ?? "Not available")
                }
            }
        }
    }
}
