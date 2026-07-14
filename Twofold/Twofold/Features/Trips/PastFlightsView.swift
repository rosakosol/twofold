//
//  PastFlightsView.swift
//  Twofold
//
//  Split out of TripsListView's main list — untethered flights no longer being tracked used to
//  live inline there as a "Past flights" section, but a couple with a long flight history had
//  that history crowd out the upcoming/active trips the main screen exists to surface. Reached
//  via a toolbar button instead, mirroring how the rest of the flight rows already behave.
//

import SwiftUI

struct PastFlightsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.pastFlights.isEmpty {
                ContentUnavailableView(
                    "No past flights",
                    systemImage: "airplane",
                    description: Text("Flights you've finished tracking will show up here.")
                )
            } else {
                List(appModel.pastFlights) { flight in
                    NavigationLink {
                        FlightTrackingView(flight: flight)
                    } label: {
                        FlightRowView(flight: flight)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await appModel.deleteFlight(flight) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Past Flights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PastFlightsView()
            .environment(AppModel())
    }
}
