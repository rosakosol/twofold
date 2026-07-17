//
//  AddFirstFlightView.swift
//  Twofold
//
//  Embeds the full shared AddFlightFlowView wizard (same real AeroAPI-backed search the live
//  app uses) rather than a reduced onboarding-only form. Flights are never self-reported —
//  once a real candidate is picked, this creates the trip, then tracks it for real via
//  AeroFlightService.addFlight. That call can fail if there's no active couple yet this early
//  in onboarding (the partner hasn't joined) — in that case the trip is saved without a flight
//  and the flow routes to the (now-mandatory) memory step, same as an explicit skip.
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
                isReunionTrip: true
            )
            do {
                try await AeroFlightService.addFlight(faFlightId: candidate.faFlightId, tripID: trip.id, travelerIDs: [trip.travelerID], notifyMe: true)
                await appModel.refreshFlights()
                // A flight was successfully tracked — skip the (now-mandatory-when-reached)
                // memory step entirely and go straight to the "ready" screen.
                onboarding.path.append(.twofoldPreview)
            } catch {
                // add-flight requires an active couple, which may not exist yet this early in
                // onboarding (partner hasn't joined) — the trip is still saved, just without a
                // flight, so this routes the same place an explicit skip would.
                onboarding.path.append(.firstMemory)
            }
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
