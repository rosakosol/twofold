//
//  TripsListView.swift
//  Twofold
//

import SwiftUI

struct TripsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var filter: TripFilter = .all
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false

    enum TripFilter: String, CaseIterable {
        case all = "All"
        case seeingEachOther = "Reunion"
        case together = "Together"
        case personal = "Personal"

        var category: TripCategory? {
            switch self {
            case .all: nil
            case .seeingEachOther: .seeingEachOther
            case .together: .together
            case .personal: .personal
            }
        }
    }

    private func traveler(for trip: Trip) -> Person {
        appModel.couple.partner(trip.travelerID) ?? appModel.currentUser
    }

    private func filtered(_ trips: [Trip]) -> [Trip] {
        guard let category = filter.category else { return trips }
        return trips.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(TripFilter.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .listRowBackground(Color.clear)

                let untetheredFlights = appModel.flights.filter { $0.tripID == nil }
                if !untetheredFlights.isEmpty {
                    Section("Tracked flights") {
                        ForEach(untetheredFlights) { flight in
                            NavigationLink {
                                FlightTrackingView(flight: flight)
                            } label: {
                                FlightRowView(flight: flight)
                            }
                        }
                    }
                }

                let upcoming = filtered(appModel.upcomingTrips)
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { trip in
                            if trip.isActive, let flight = trip.flight {
                                NavigationLink {
                                    FlightTrackingView(flight: flight)
                                } label: {
                                    TripRowView(trip: trip, traveler: traveler(for: trip))
                                }
                            } else {
                                TripRowView(trip: trip, traveler: traveler(for: trip))
                            }
                        }
                    }
                }

                let past = filtered(appModel.pastTrips)
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { trip in
                            TripRowView(trip: trip, traveler: traveler(for: trip))
                        }
                    }
                }

                if appModel.trips.isEmpty {
                    Section {
                        emptyStateHint
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAddTrip = true
                        } label: {
                            Label("Add Trip", systemImage: "airplane")
                        }
                        Button {
                            showingAddFlight = true
                        } label: {
                            Label("Add Flight", systemImage: "ticket")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                NavigationStack {
                    AddTripDetailsView(mode: .standalone, partnerName: appModel.partner.name) { _ in
                        showingAddTrip = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingAddTrip = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddFlight) {
                AddFlightView()
            }
        }
    }

    private var emptyStateHint: some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: "airplane.circle.fill").foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your first trip").font(.headline)
                    Text("Tap + above to plan a reunion, a trip together, or something of your own.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

#Preview {
    TripsListView()
        .environment(AppModel())
}
