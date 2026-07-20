//
//  AddFlightFlowView.swift
//  Twofold
//
//  Multi-step "Add Flight" wizard shared by the live app's AddFlightView and onboarding's
//  AddTripDetailsView (sheeted from its "attach a flight" row). Owns its own internal
//  NavigationStack (nested inside whichever presentation context the caller uses) so its
//  per-step titles/subtitles don't have to fit OnboardingScaffold's single title+pinned-CTA
//  chrome.
//

import CoreLocation
import SwiftUI

struct AddFlightFlowView: View {
    /// What happens once the user has picked one specific real flight.
    enum Completion {
        /// Live app: push the existing FlightConfirmationView (trip-link + notify + add-flight),
        /// which owns its own dismissal.
        case confirmAndTrack(onDone: () -> Void)
        /// Onboarding: hand the candidate back to the caller; the flow persists nothing itself.
        case handOff((AeroFlightCandidate) -> Void)
    }

    private let completion: Completion
    @State private var model: AddFlightFlowModel

    init(
        nearCoordinate: CLLocationCoordinate2D?,
        initialFlightNumberDigits: String? = nil,
        topBarTitle: String = "Cancel",
        onTopBarAction: @escaping () -> Void,
        completion: Completion
    ) {
        self.completion = completion
        _model = State(initialValue: AddFlightFlowModel(
            nearCoordinate: nearCoordinate,
            topBarTitle: topBarTitle,
            onTopBarAction: onTopBarAction,
            initialFlightNumberDigits: initialFlightNumberDigits
        ))
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            AddFlightEntryStepView()
                .navigationDestination(for: AddFlightFlowStep.self) { step in
                    destination(for: step)
                }
        }
        .environment(model)
    }

    @ViewBuilder
    private func destination(for step: AddFlightFlowStep) -> some View {
        switch step {
        case .flightNumber:
            FlightNumberStepView()
        case .airlinePicker:
            AirlinePickerStepView()
        case .airport(let role):
            AirportPickerStepView(role: role)
        case .date:
            AddFlightDateStepView()
        case .results:
            AddFlightResultsStepView(completion: completion)
        }
    }
}
