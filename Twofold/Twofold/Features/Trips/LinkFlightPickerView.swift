//
//  LinkFlightPickerView.swift
//  Twofold
//
//  Lets you attach an already-tracked flight to a trip after the fact — the only other place a
//  flight gets a trip_id is at add-flight time (FlightConfirmationView's "Link to a trip"
//  picker), which only offers flightless trips going the other direction. This closes the gap:
//  starting from the trip, offering flights that don't already belong to one — or, via "Create a
//  new flight", searching AeroAPI for one from scratch, preselected to link straight to this trip.
//

import PostHog
import SwiftUI

struct LinkFlightPickerView: View {
    let trip: Trip

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateFlight = false

    private var untetheredFlights: [Flight] {
        appModel.flights.filter { $0.tripID == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCreateFlight = true
                    } label: {
                        Label("Create a new flight", systemImage: "plus.circle.fill")
                    }
                }
                Section("Unlinked flights") {
                    if untetheredFlights.isEmpty {
                        Text("Every tracked flight is already linked to a trip.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    } else {
                        ForEach(untetheredFlights) { flight in
                            Button {
                                Task {
                                    await appModel.linkFlight(flight, to: trip)
                                    dismiss()
                                }
                            } label: {
                                FlightRowView(flight: flight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Link a Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingCreateFlight) {
            AddFlightFlowView(
                nearCoordinate: appModel.currentUser.homeCity?.coordinate,
                initialTripID: trip.id,
                topBarTitle: "Cancel",
                onTopBarAction: { showingCreateFlight = false },
                completion: .confirmAndTrack(onDone: {
                    showingCreateFlight = false
                    dismiss()
                })
            )
        }
        .postHogScreenView("Travel: Link Flight")
    }
}

#Preview {
    LinkFlightPickerView(trip: MockData.reunionTrip)
        .environment(AppModel())
}
