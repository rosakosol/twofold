//
//  AddFirstFlightView.swift
//  Twofold
//
//  Embeds the full shared AddFlightFlowView wizard (same real AeroAPI-backed search the live
//  app uses) rather than a reduced onboarding-only form. Once a real candidate is picked, this
//  immediately creates a trip with a self-reported Flight using the real resolved number/date
//  (the proven-reliable path this screen already used), then best-effort upgrades it to a real
//  AeroAPI-tracked flight — wrapped in try? since add-flight requires an active couple, which
//  may not exist yet this early if the partner hasn't joined. Either way lands on .firstMemory.
//

import SwiftUI

struct AddFirstFlightView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    var body: some View {
        AddFlightFlowView(
            nearCoordinate: onboarding.homeCity?.coordinate,
            topBarTitle: "Add this later",
            onTopBarAction: { onboarding.path.append(.firstMemory) },
            completion: .handOff(handleSelected)
        )
    }

    private func handleSelected(_ candidate: AeroFlightCandidate) {
        onboarding.draftedFlightNumber = candidate.displayFlightNumber
        onboarding.draftedFlightDate = candidate.scheduledOut

        guard let origin = onboarding.partnerCity, let destination = onboarding.homeCity else {
            onboarding.path.append(.firstMemory)
            return
        }

        Task {
            let trip = await appModel.addTrip(
                origin: origin,
                destination: destination,
                departureDate: candidate.scheduledOut ?? Date.now,
                arrivalDate: candidate.scheduledIn ?? Date.now.addingTimeInterval(3600 * 4),
                traveler: .partner,
                category: .seeingEachOther,
                flightNumber: candidate.displayFlightNumber
            )
            // Best-effort upgrade to a real AeroAPI-tracked flight — silent on failure since
            // add-flight requires an active couple, which may not exist yet this early in
            // onboarding. The self-reported trip above is the safety net either way.
            try? await AeroFlightService.addFlight(faFlightId: candidate.faFlightId, tripID: trip.id, notifyMe: true)
            await appModel.refreshFlights()
            // A flight was successfully added — skip the (now-mandatory-when-reached) memory
            // step entirely and go straight to the "ready" screen. Only the top-bar skip and
            // the missing-city guard above land on .firstMemory instead.
            onboarding.path.append(.twofoldPreview)
        }
    }
}

#Preview {
    NavigationStack {
        AddFirstFlightView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
