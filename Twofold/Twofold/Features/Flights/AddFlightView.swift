//
//  AddFlightView.swift
//  Twofold
//
//  Progressive home-card sheet for attaching a flight to a trip that doesn't have one yet.
//

import SwiftUI

struct AddFlightView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTripID: Trip.ID?
    @State private var flightNumber = ""

    private var tripsWithoutFlight: [Trip] {
        appModel.trips.filter { $0.flight == nil }
    }

    var body: some View {
        NavigationStack {
            OnboardingScaffold(
                title: "Add your first flight",
                subtitle: "Attach a flight to one of your trips to start tracking it.",
                content: {
                    VStack(spacing: Theme.Spacing.sm) {
                        if tripsWithoutFlight.isEmpty {
                            Text("Every trip already has a flight attached.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.subtleInk)
                        } else {
                            ForEach(tripsWithoutFlight) { trip in
                                OnboardingOptionRow(
                                    title: "\(trip.origin.iataCode ?? trip.origin.city) → \(trip.destination.iataCode ?? trip.destination.city)",
                                    isSelected: selectedTripID == trip.id
                                ) {
                                    selectedTripID = trip.id
                                }
                            }

                            TextField("Flight number, e.g. QF35", text: $flightNumber)
                                .textInputAutocapitalization(.characters)
                                .padding()
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                    }
                },
                primaryTitle: "Save",
                primaryAction: save,
                primaryDisabled: selectedTripID == nil || flightNumber.trimmingCharacters(in: .whitespaces).isEmpty
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let selectedTripID else { return }
        appModel.addFlight(to: selectedTripID, flightNumber: flightNumber)
        dismiss()
    }
}

#Preview {
    AddFlightView()
        .environment(AppModel())
}
