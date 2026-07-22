//
//  TripsListView.swift
//  Twofold
//
//  Full-screen interactive globe (`TripsGlobeView`) with an always-present browse sheet docked to
//  the bottom — same peek/expand mechanics `MemoriesMapView` already established
//  (`.presentationDetents([peek, .large], selection:)` + `.presentationBackgroundInteraction`, so
//  the globe stays pannable/zoomable while the sheet is only peeking). At the peek height the
//  sheet shows a horizontal card carousel (upcoming trips or tracked flights, depending on the
//  Trips/Flights picker); dragged to `.large` it swaps to the full Upcoming/Past (or Tracked/Past)
//  list, which is how Past trips/flights stay reachable. Tapping any card or row opens that trip's
//  or flight's own details as a *separate* partial-height sheet, rather than pushing — "tap
//  opens a partial screen from the bottom" applies to trip/flight detail, not to browsing itself.
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
    /// Never set back to false — this sheet is meant to always be showing, just moving between
    /// its peek and full heights, not something the user can dismiss outright (there'd be nothing
    /// left to bring it back).
    @State private var showingBrowseSheet = true
    @State private var sheetDetent: PresentationDetent = Self.peekDetent
    @State private var selectedTrip: Trip?
    @State private var selectedFlight: Flight?

    private static let peekDetent: PresentationDetent = .height(220)

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
            TripsGlobeView(
                trips: appModel.upcomingTrips,
                travelers: travelers(for:),
                fallbackCenter: appModel.currentUser.homeCity?.coordinate
            )
            .ignoresSafeArea()
            .sheet(isPresented: $showingBrowseSheet) {
                browseSheet
                    .presentationDetents([Self.peekDetent, .large], selection: $sheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: Self.peekDetent))
                    .interactiveDismissDisabled()
            }
        }
        .sheet(item: $selectedTrip) { trip in
            NavigationStack {
                TripDetailsView(trip: trip)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedFlight) { flight in
            NavigationStack {
                FlightTrackingView(flight: flight)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    // MARK: - Browse sheet

    private var browseSheet: some View {
        VStack(spacing: 0) {
            browseHeader

            if sheetDetent == Self.peekDetent {
                peekContent
            } else {
                expandedContent
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var browseHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            Picker("Section", selection: $tab) {
                ForEach(TripsTab.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

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
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.skyBlue)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var peekContent: some View {
        switch tab {
        case .trips:
            if appModel.trips.isEmpty {
                emptyTripsHint.padding(.horizontal, Theme.Spacing.md)
                Spacer(minLength: 0)
            } else {
                carousel(appModel.upcomingTrips) { trip in
                    Button {
                        selectedTrip = trip
                    } label: {
                        TripCarouselCard(trip: trip, travelers: travelers(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .flights:
            if appModel.flights.isEmpty {
                emptyFlightsHint.padding(.horizontal, Theme.Spacing.md)
                Spacer(minLength: 0)
            } else {
                carousel(appModel.activeOrUpcomingFlights) { flight in
                    Button {
                        selectedFlight = flight
                    } label: {
                        FlightCarouselCard(flight: flight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func carousel<Item: Identifiable, CardContent: View>(
        _ items: [Item],
        @ViewBuilder card: @escaping (Item) -> CardContent
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(items) { item in
                    card(item)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Spacing.md)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var expandedContent: some View {
        List {
            if tab == .trips, appModel.trips.isEmpty {
                emptyTripsHint
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else if tab == .flights, appModel.flights.isEmpty {
                emptyFlightsHint
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            switch tab {
            case .trips:
                tripSections
            case .flights:
                flightSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var tripSections: some View {
        let upcoming = appModel.upcomingTrips
        if !upcoming.isEmpty {
            Section("Upcoming") {
                ForEach(upcoming) { trip in
                    Button {
                        selectedTrip = trip
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        let past = appModel.pastTrips
        if !past.isEmpty {
            Section("Past") {
                ForEach(past) { trip in
                    Button {
                        selectedTrip = trip
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                    .buttonStyle(.plain)
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
        Button {
            selectedFlight = flight
        } label: {
            FlightRowView(flight: flight)
        }
        .buttonStyle(.plain)
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
