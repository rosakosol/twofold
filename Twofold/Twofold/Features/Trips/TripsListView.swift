//
//  TripsListView.swift
//  Twofold
//

import SwiftUI

struct TripsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tab: TripsTab = .trips
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    /// Tapping the solo-state empty hints below opens this rather than the add-trip/add-flight
    /// sheet — there's a real partner-required blocker before either of those would even work.
    @State private var showingPartnerGate = false

    enum TripsTab: String, CaseIterable {
        case trips = "Trips"
        case flights = "Flights"
    }

    private func travelers(for trip: Trip) -> [Person] {
        let people = trip.travelerIDs.compactMap { appModel.couple.partner($0) }
        return people.isEmpty ? [appModel.currentUser] : people
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Section", selection: $tab) {
                        ForEach(TripsTab.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Theme.Spacing.sm)

                    if tab == .trips, appModel.trips.isEmpty {
                        emptyTripsHint
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else if tab == .flights, appModel.flights.isEmpty {
                        emptyFlightsHint
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listRowBackground(Color.clear)

                switch tab {
                case .trips:
                    tripSections
                case .flights:
                    flightSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Travel")
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
                            Label("Add Flight", image: "boarding-pass")
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
            .sheet(isPresented: $showingPartnerGate) {
                PartnerRequiredGateView()
            }
        }
    }

    @ViewBuilder
    private var tripSections: some View {
        let upcoming = appModel.upcomingTrips
        if !upcoming.isEmpty {
            Section("Upcoming") {
                ForEach(upcoming) { trip in
                    NavigationLink {
                        TripDetailsView(trip: trip)
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                }
            }
        }

        let past = appModel.pastTrips
        if !past.isEmpty {
            Section("Past") {
                ForEach(past) { trip in
                    NavigationLink {
                        TripDetailsView(trip: trip)
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                }
            }
        }
    }

    /// Tracked flights (soonest departure first, see `AppModel.activeOrUpcomingFlights`) above
    /// completed ones — every flight ever added lives in this one tab now, trip-linked or not,
    /// rather than splitting untethered ones off into a separate Past Flights screen.
    @ViewBuilder
    private var flightSections: some View {
        let tracked = appModel.activeOrUpcomingFlights
        if !tracked.isEmpty {
            Section("Tracked flights") {
                ForEach(tracked) { flight in
                    flightRow(flight)
                }
            }
        }

        let completed = appModel.completedFlights
        if !completed.isEmpty {
            Section("Past flights") {
                ForEach(completed) { flight in
                    flightRow(flight)
                }
            }
        }
    }

    private func flightRow(_ flight: Flight) -> some View {
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

    @ViewBuilder
    private var emptyTripsHint: some View {
        if appModel.partnerConnected {
            Button {
                showingAddTrip = true
            } label: {
                emptyHintCard(icon: "airplane.circle.fill", title: "Add your first trip", subtitle: "Tap to plan a reunion or a trip of your own.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        } else {
            Button {
                showingPartnerGate = true
            } label: {
                emptyHintCard(icon: "person.2.fill", title: "Invite your partner to add your first trip together", subtitle: "Trips are better planned together.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var emptyFlightsHint: some View {
        if appModel.partnerConnected {
            Button {
                showingAddFlight = true
            } label: {
                emptyHintCard(icon: "airplane.circle.fill", title: "Add your first flight", subtitle: "Track a flight to see it here.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        } else {
            Button {
                showingPartnerGate = true
            } label: {
                emptyHintCard(icon: "person.2.fill", title: "Invite your partner to share your first tracked flight", subtitle: "Track flights together once you're connected.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private func emptyHintCard(icon: String, title: String, subtitle: String) -> some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: icon).foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    TripsListView()
        .environment(AppModel())
}
