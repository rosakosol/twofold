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
//  AddFlightFlowView owns its own internal NavigationStack, so it's presented here in a sheet
//  rather than rendered directly as this screen's body — matching how the live app's
//  AddFlightView and AddTripDetailsView both already use it. Rendering it directly used to push
//  a second, independently-typed NavigationStack as a destination of the outer onboarding
//  NavigationStack; with both stacks' paths getting mutated around the same time (this screen's
//  own async `onboarding.path.append` calls, layered on top of the flow's own step pushes),
//  that's a known SwiftUI crash — `AnyNavigationPath.Error.comparisonTypeMismatch` — which is
//  what was happening here. A sheet keeps the two NavigationStacks in separate presentation
//  contexts, which SwiftUI handles fine.
//

import SwiftUI

struct AddFirstFlightView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var showingFlow = false
    /// Where the outer onboarding path advances to once the sheet is gone — read in `onDismiss`,
    /// never appended to while `AddFlightFlowView`'s sheet (and its own nested NavigationStack)
    /// is still up.
    @State private var nextStep: OnboardingStep = .firstMemory

    var body: some View {
        Theme.backgroundGradient.ignoresSafeArea()
            .onAppear { showingFlow = true }
            .sheet(isPresented: $showingFlow, onDismiss: { onboarding.path.append(nextStep) }) {
                AddFlightFlowView(
                    nearCoordinate: onboarding.homeCity?.coordinate,
                    topBarTitle: "Add this later",
                    onTopBarAction: { showingFlow = false },
                    completion: .handOff(handleSelected)
                )
            }
    }

    private func handleSelected(_ candidate: AeroFlightCandidate) {
        onboarding.draftedFlightNumber = candidate.displayFlightNumber
        onboarding.draftedFlightDate = candidate.scheduledOut

        guard let origin = onboarding.partnerCity, let destination = onboarding.homeCity else {
            showingFlow = false
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
                nextStep = .twofoldPreview
            } catch {
                // add-flight requires an active couple, which may not exist yet this early in
                // onboarding (partner hasn't joined) — the trip is still saved, just without a
                // flight, so this routes the same place an explicit skip would (nextStep's
                // .firstMemory default, untouched here).
            }
            showingFlow = false
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
