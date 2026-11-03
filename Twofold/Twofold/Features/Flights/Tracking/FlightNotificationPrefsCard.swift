//
//  FlightNotificationPrefsCard.swift
//  Twofold
//
//  Flight Details' "Notify me about" toggles.
//

import SwiftUI

// Notification preferences — individually-bound so the toggles feel instant; saved as one
// upsert on change.
struct FlightNotificationToggles {
    var gateTerminalChanges = true
    var delayOrCancellation = true
    var departureNotif = true
    var landingNotif = true
    var arrivalAtGateNotif = true
    var baggageClaimNotif = true
}

struct FlightNotificationPrefsCard: View {
    @Binding var toggles: FlightNotificationToggles
    /// Called after any one toggle changes.
    let onChange: () -> Void

    var body: some View {
        SectionCard {
            Text("Notify me about").font(.subheadline.weight(.semibold))
            Toggle("Gate & terminal changes", isOn: $toggles.gateTerminalChanges).font(.subheadline)
            Toggle("Delays & cancellations", isOn: $toggles.delayOrCancellation).font(.subheadline)
            Toggle("Departure", isOn: $toggles.departureNotif).font(.subheadline)
            Toggle("Landing", isOn: $toggles.landingNotif).font(.subheadline)
            Toggle("Arrival at gate", isOn: $toggles.arrivalAtGateNotif).font(.subheadline)
            Toggle("Baggage claim", isOn: $toggles.baggageClaimNotif).font(.subheadline)
        }
        .onChange(of: toggles.gateTerminalChanges) { _, _ in onChange() }
        .onChange(of: toggles.delayOrCancellation) { _, _ in onChange() }
        .onChange(of: toggles.departureNotif) { _, _ in onChange() }
        .onChange(of: toggles.landingNotif) { _, _ in onChange() }
        .onChange(of: toggles.arrivalAtGateNotif) { _, _ in onChange() }
        .onChange(of: toggles.baggageClaimNotif) { _, _ in onChange() }
    }
}
